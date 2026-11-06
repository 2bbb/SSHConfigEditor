import XCTest
@testable import SSHConfigCore

final class ConfigTests: XCTestCase {
    func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SSHConfigTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testFieldEditPreservesCommentsUnknownDirectivesAndCRLF() throws {
        let original = "# comment\r\nHost sample\r\n\tHostName=\"old host\"  # keep me\r\n    SomeFutureOption value\r\n\r\nHost other\r\n    User admin"
        var doc = ConfigDocument(original)
        try doc.setValue("HostName", value: "new.example", blockID: 1)
        XCTAssertEqual(doc.text, original.replacingOccurrences(of: "\"old host\"", with: "new.example"))
        try doc.setValue("User", value: "deploy", blockID: 1)
        XCTAssertTrue(doc.text.contains("Host sample\r\n    User deploy\r\n"))
        XCTAssertTrue(doc.text.hasSuffix("    User admin"))
    }

    func testDuplicateIdentityFilesAreNeverCollapsed() throws {
        var doc = ConfigDocument("Host sample\n    IdentityFile ~/.ssh/a\n    IdentityFile ~/.ssh/b\n")
        let original = doc.text
        XCTAssertThrowsError(try doc.setValue("IdentityFile", value: "other", blockID: 0))
        XCTAssertEqual(doc.text, original)
    }

    func testClearingHostWhileTypingDoesNotMergeBlocks() throws {
        var doc = ConfigDocument("Host first\nUser alice\nHost second\nUser bob\n")
        try doc.setValue("Host", value: "", blockID: 0)
        XCTAssertEqual(doc.blocks.count, 2)
        XCTAssertEqual(doc.value("User", in: doc.blocks[1]), "bob")
        XCTAssertFalse(doc.diagnostics.isEmpty)
    }
    func testOutgoingBlockCanRenderAfterItsSourceWasShortenedByMove() {
        let before = ConfigDocument("Host first\n User alice\n\nHost second\n HostName second.example\n")
        let outgoing = before.blocks[1]
        let after = ConfigDocument("")
        XCTAssertEqual(after.value("HostName", in: outgoing), "")
        XCTAssertEqual(after.source(in: outgoing), "")
    }

    func testLexerQuotesCommentsEqualsAndMatchBoundaries() {
        let directive = Directive.parse("  Include = \"conf.d/with space.conf\" conf.d/*.conf # comment")!
        XCTAssertEqual(directive.arguments, ["conf.d/with space.conf", "conf.d/*.conf"])
        let doc = ConfigDocument("Host one\n  User alice\nMatch host two\n  User bob\nHost *\n  Port 22\n")
        XCTAssertEqual(doc.blocks.map(\.kind), ["host", "match", "host"])
        XCTAssertEqual(doc.value("User", in: doc.blocks[0]), "alice")
        XCTAssertTrue(ConfigDocument("Host foo\nPort 70000\n").diagnostics.contains { $0.contains("Port") })
    }

    func testIncludeUsesSSHBaseLexicalOrderAndDetectsCycle() throws {
        let root = try fixture()
        let conf = root.appendingPathComponent("conf.d")
        try FileManager.default.createDirectory(at: conf, withIntermediateDirectories: true)
        let main = root.appendingPathComponent("config")
        try "Include conf.d/*.conf\n".write(to: main, atomically: true, encoding: .utf8)
        try "Include config\n".write(to: conf.appendingPathComponent("a.conf"), atomically: true, encoding: .utf8)
        try "Host b\nUser bob\n".write(to: conf.appendingPathComponent("b.conf"), atomically: true, encoding: .utf8)
        let graph = IncludeGraph(baseDirectory: root).build(root: main) { try String(contentsOf: $0, encoding: .utf8) }
        let children = try XCTUnwrap(graph.children?.first?.children)
        XCTAssertEqual(children.map(\.title), ["a.conf", "b.conf"])
        XCTAssertEqual(children[0].children?.first?.children?.first?.note, "Include cycle")
        let pending = conf.appendingPathComponent("c.conf")
        XCTAssertEqual(try IncludeGraph(baseDirectory: root).expand("conf.d/*.conf", pendingFiles: [pending]).map(\.lastPathComponent), ["a.conf", "b.conf", "c.conf"])
    }

    func testSaveBackupPermissionsConflictAndSymlink() throws {
        let dir = try fixture()
        let target = dir.appendingPathComponent("target")
        let link = dir.appendingPathComponent("config")
        let backups = dir.appendingPathComponent("backups")
        try "Host original\n".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: target.path)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        var (snapshot, _) = try FileSnapshot.load(link)
        let backup = try XCTUnwrap(snapshot.save("Host edited\n", backupRoot: backups))
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "Host original\n")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "Host edited\n")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int, 0o640)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? Int, 0o600)
        try "Host external\n".write(to: target, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try snapshot.save("Host overwritten\n", backupRoot: backups))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "Host external\n")
    }

    func testNewFileCollisionAndPrivateKeyAreRejected() throws {
        let dir = try fixture(), url = dir.appendingPathComponent("new.conf")
        var (snapshot, _) = try FileSnapshot.load(url)
        try "created externally".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try snapshot.save("new contents", backupRoot: dir.appendingPathComponent("backup")))
        try "-----BEGIN OPENSSH PRIVATE KEY-----\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try FileSnapshot.load(url))
    }

    func testOpenSSHReadsSavedFixtureWithFirstValuePrecedence() throws {
        let dir = try fixture(), child = dir.appendingPathComponent("child.conf"), root = dir.appendingPathComponent("config")
        try "Host fixture\n    User included\n".write(to: child, atomically: true, encoding: .utf8)
        var doc = ConfigDocument("Include \"\(child.path)\"\nHost fixture\n    HostName fixture.invalid\n    User later\n    Port 22\n")
        try doc.setValue("Port", value: "2222", blockID: 1)
        var (snapshot, _) = try FileSnapshot.load(root)
        try snapshot.save(doc.text, backupRoot: dir.appendingPathComponent("backup"))
        let task = Process(), output = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        // Only our controlled fixture: no exec, canonicalization, proxy or network connection.
        task.arguments = ["-G", "-F", root.path, "fixture"]
        task.standardOutput = output; task.standardError = FileHandle.nullDevice
        try task.run()
        let result = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
        task.waitUntilExit()
        XCTAssertEqual(task.terminationStatus, 0)
        XCTAssertTrue(result.contains("user included\n"))
        XCTAssertTrue(result.contains("port 2222\n"))
        XCTAssertTrue(result.contains("hostname fixture.invalid\n"))
    }
}
