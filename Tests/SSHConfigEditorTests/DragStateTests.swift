import XCTest
@testable import SSHConfigEditor

@MainActor final class DragStateTests: XCTestCase {
    func workspace() throws -> Workspace {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SSHDrag-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("conf.d"), withIntermediateDirectories: true)
        try "Include conf.d/*.conf\n".write(to: directory.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        try "Host moving\n User alice\n".write(to: directory.appendingPathComponent("conf.d/a.conf"), atomically: true, encoding: .utf8)
        try "Host target\n User bob\n".write(to: directory.appendingPathComponent("conf.d/b.conf"), atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return Workspace(root: directory.appendingPathComponent("config"), includeBase: directory, backups: directory.appendingPathComponent("backups"))
    }
    func testHoverOpensInsertionTargetThenDropMovesWithoutWritingDisk() async throws {
        let model = try workspace()
        let source = model.files.first { $0.name == "a.conf" }!, target = model.files.first { $0.name == "b.conf" }!
        _ = model.beginDrag(file: source, block: source.parsed.blocks[0])
        model.hoverFile(target)
        XCTAssertNil(model.springFileID)
        try await Task.sleep(for: .milliseconds(850))
        XCTAssertEqual(model.springFileID, target.id)
        XCTAssertEqual(model.selectedFileID, target.id)
        XCTAssertTrue(model.dirtyFiles.isEmpty)
        XCTAssertTrue(model.moveDraggedHost(to: target, before: 0))
        XCTAssertEqual(target.parsed.blocks.filter { $0.kind == "host" }.map(\.title), ["moving", "target"])
        XCTAssertEqual(model.dirtyFiles.count, 2)
        XCTAssertEqual(model.selectedBlockID, target.parsed.blocks.first { $0.title == "moving" }?.id)
        XCTAssertNil(model.dragSession)
        XCTAssertNil(model.springFileID)
        XCTAssertTrue(try String(contentsOf: source.snapshot.url, encoding: .utf8).contains("Host moving"))
        XCTAssertFalse(try String(contentsOf: target.snapshot.url, encoding: .utf8).contains("Host moving"))
    }
    func testCancelledHoverNeverChangesSelectionOrFiles() async throws {
        let model = try workspace()
        let source = model.files.first { $0.name == "a.conf" }!, target = model.files.first { $0.name == "b.conf" }!
        model.select(path: source.snapshot.url.path)
        _ = model.beginDrag(file: source, block: source.parsed.blocks[0])
        model.hoverFile(target)
        model.leaveFile(target)
        model.endDrag()
        try await Task.sleep(for: .milliseconds(850))
        XCTAssertEqual(model.selectedFileID, source.id)
        XCTAssertNil(model.springFileID)
        XCTAssertNil(model.dragSession)
        XCTAssertTrue(model.dirtyFiles.isEmpty)
    }
    func testNestedRenameRemainsInHierarchyAfterReload() throws {
        let model = try workspace()
        let source = model.files.first { $0.name == "a.conf" }!
        XCTAssertTrue(model.rename(source, to: "hoge/bar"))
        XCTAssertEqual(model.selected?.name, "bar")
        let conf = try XCTUnwrap(model.fileTree.first { $0.title == "conf.d" })
        XCTAssertEqual(conf.children.first { $0.title == "hoge" }?.children.first?.title, "bar")
        let reopened = Workspace(root: model.rootURL, includeBase: model.baseURL, backups: model.backupRoot)
        XCTAssertTrue(reopened.files.contains { $0.name == "bar" })
    }
}
