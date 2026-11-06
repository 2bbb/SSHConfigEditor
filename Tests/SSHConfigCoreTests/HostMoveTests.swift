import XCTest
@testable import SSHConfigCore

final class HostMoveTests: XCTestCase {
    func testAppendMovesWholeHostAndItsCommentsWithoutChangingOtherBlocks() throws {
        let source = "# first host\nHost one\n User alice\n UnknownDirective keep\n\n# second host\nHost two\n User bob\n"
        let result = try HostMoveResult(source: source, blockID: 1, destination: "Host existing\n User carol")
        XCTAssertEqual(result.source, "# second host\nHost two\n User bob\n")
        XCTAssertEqual(result.destination, "Host existing\n User carol\n\n# first host\nHost one\n User alice\n UnknownDirective keep\n")
        XCTAssertEqual(ConfigDocument(result.destination).blocks.last?.id, result.insertedBlockID)
    }
    func testInsertionBeforeHostKeepsGlobalSettingsAndTargetCommentsInPlace() throws {
        let source = "Host moving\n Port 2222\n"
        let destination = "Include conf.d/*.conf\r\n\r\n# target\r\nHost existing\r\n User bob\r\n"
        let result = try HostMoveResult(source: source, blockID: 0, destination: destination, beforeBlockID: 1)
        XCTAssertEqual(result.source, "")
        XCTAssertEqual(result.destination, "Include conf.d/*.conf\r\n\r\nHost moving\r\n Port 2222\r\n\r\n# target\r\nHost existing\r\n User bob\r\n")
    }
    func testMatchCannotBeMovedAndGlobalCannotBeInsertionTarget() throws {
        XCTAssertThrowsError(try HostMoveResult(source: "Match all\nUser bob\n", blockID: 0, destination: ""))
        XCTAssertThrowsError(try HostMoveResult(source: "Host moving\n", blockID: 0, destination: "User alice\nHost other\n", beforeBlockID: 0))
    }
}
