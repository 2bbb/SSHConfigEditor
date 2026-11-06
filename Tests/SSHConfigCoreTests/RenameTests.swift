import XCTest
@testable import SSHConfigCore

final class RenameTests: XCTestCase {
    func fixture() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SSHRename-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("conf.d"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }
    func testRenameUpdatesEveryLiteralReferencePreservingOtherArgumentsAndComments() throws {
        let dir = try fixture(), root = dir.appendingPathComponent("config"), nested = dir.appendingPathComponent("nested.conf")
        let old = dir.appendingPathComponent("conf.d/old.conf")
        let texts = [root: "# keep\r\nInclude = conf.d/old.conf \"other file\"  # note\r\n",
                     nested: "Host *\n    Include \"\(old.path)\"\n", old: "Host sample\nUser alice\n"]
        for (url, text) in texts { try text.write(to: url, atomically: true, encoding: .utf8) }
        let plan = try FileRenamePlan(source: old, newName: "new name.conf", documents: texts, baseDirectory: dir)
        XCTAssertEqual(plan.rewrites.count, 2)
        try plan.apply(snapshots: texts.keys.map { try FileSnapshot.load($0).0 }, backupRoot: dir.appendingPathComponent("backup"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try String(contentsOf: plan.destination, encoding: .utf8), texts[old])
        XCTAssertEqual(try String(contentsOf: root, encoding: .utf8), "# keep\r\nInclude = \"conf.d/new name.conf\" \"other file\"  # note\r\n")
        XCTAssertTrue(try String(contentsOf: nested, encoding: .utf8).contains("new name.conf\""))
    }
    func testGlobIsPreservedAndEscapingGlobGetsExplicitReference() throws {
        let dir = try fixture(), root = dir.appendingPathComponent("config"), old = dir.appendingPathComponent("conf.d/old.conf")
        try "Host sample\n".write(to: old, atomically: true, encoding: .utf8)
        let same = try FileRenamePlan(source: old, newName: "new.conf", documents: [root: "Include conf.d/*.conf\n"], baseDirectory: dir)
        XCTAssertTrue(same.rewrites.isEmpty)
        let changed = try FileRenamePlan(source: old, newName: "new.settings", documents: [root: "Include conf.d/*.conf # keep\n"], baseDirectory: dir)
        XCTAssertEqual(changed.rewrites[0].after, "Include conf.d/*.conf \"\(dir.path)/conf.d/new.settings\" # keep\n")
    }
    func testNestedPathCreatesDirectoriesAndUpdatesReference() throws {
        let dir = try fixture(), root = dir.appendingPathComponent("config"), old = dir.appendingPathComponent("conf.d/old.conf")
        let texts = [root: "Include conf.d/old.conf\n", old: "Host sample\n"]
        for (url, text) in texts { try text.write(to: url, atomically: true, encoding: .utf8) }
        let plan = try FileRenamePlan(source: old, newName: "hoge/bar", documents: texts, baseDirectory: dir)
        try plan.apply(snapshots: texts.keys.map { try FileSnapshot.load($0).0 }, backupRoot: dir.appendingPathComponent("backup"))
        XCTAssertEqual(plan.destination.path, dir.appendingPathComponent("conf.d/hoge/bar").path)
        XCTAssertEqual(try String(contentsOf: root, encoding: .utf8), "Include \"conf.d/hoge/bar\"\n")
        XCTAssertEqual(try String(contentsOf: plan.destination, encoding: .utf8), "Host sample\n")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: plan.destination.deletingLastPathComponent().path)[.posixPermissions] as? Int, 0o700)
        XCTAssertThrowsError(try FileRenamePlan(source: plan.destination, newName: "../outside", documents: [:], baseDirectory: dir))
    }
    func testExternalReferenceChangeAndDestinationCollisionLeaveSourceInPlace() throws {
        let dir = try fixture(), root = dir.appendingPathComponent("config"), old = dir.appendingPathComponent("conf.d/old.conf")
        let texts = [root: "Include conf.d/old.conf\n", old: "Host sample\n"]
        for (url, text) in texts { try text.write(to: url, atomically: true, encoding: .utf8) }
        let snapshots = try texts.keys.map { try FileSnapshot.load($0).0 }
        let plan = try FileRenamePlan(source: old, newName: "new.conf", documents: texts, baseDirectory: dir)
        try "# external\n".write(to: root, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try plan.apply(snapshots: snapshots, backupRoot: dir.appendingPathComponent("backup")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        try "collision".write(to: plan.destination, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try FileRenamePlan(source: old, newName: "new.conf", documents: texts, baseDirectory: dir))
        XCTAssertEqual(try String(contentsOf: plan.destination, encoding: .utf8), "collision")
    }
    func testReferenceWriteFailureRollsBackMove() throws {
        let dir = try fixture(), root = dir.appendingPathComponent("a.conf"), old = dir.appendingPathComponent("conf.d/old.conf")
        let texts = [root: "Include conf.d/old.conf\n", old: "Host sample\n"]
        for (url, text) in texts { try text.write(to: url, atomically: true, encoding: .utf8) }
        let plan = try FileRenamePlan(source: old, newName: "new.conf", documents: texts, baseDirectory: dir)
        let invalidBackupRoot = dir.appendingPathComponent("not-a-directory")
        try "block backup".write(to: invalidBackupRoot, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try plan.apply(snapshots: texts.keys.map { try FileSnapshot.load($0).0 }, backupRoot: invalidBackupRoot))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.destination.path))
        XCTAssertEqual(try String(contentsOf: root, encoding: .utf8), texts[root])
    }
}
