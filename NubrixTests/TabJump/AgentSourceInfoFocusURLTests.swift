import XCTest
@testable import Nubrix

final class AgentSourceInfoFocusURLTests: XCTestCase {
    private let hex = "0123456789abcdef0123456789abcdef"

    private func focusURL(_ value: String) -> String {
        AgentSourceInfo(headers: ["x-nubrix-focus-url": value]).focusURL
    }

    func testAcceptsWarpURL() {
        XCTAssertEqual(focusURL("warp://session/\(hex)"), "warp://session/\(hex)")
    }

    func testAcceptsWarpPreviewURL() {
        XCTAssertEqual(focusURL("warppreview://session/\(hex)"), "warppreview://session/\(hex)")
    }

    func testRejectsUppercaseHex() {
        XCTAssertEqual(focusURL("warp://session/\(hex.uppercased())"), "")
    }

    func testRejectsWrongHexLength() {
        XCTAssertEqual(focusURL("warp://session/\(hex.dropLast())"), "")
        XCTAssertEqual(focusURL("warp://session/\(hex)0"), "")
    }

    func testRejectsOtherSchemes() {
        XCTAssertEqual(focusURL("https://session/\(hex)"), "")
        XCTAssertEqual(focusURL("warp1://session/\(hex)"), "")
    }

    func testRejectsExtraPathQueryAndInjection() {
        XCTAssertEqual(focusURL("warp://session/\(hex)/x"), "")
        XCTAssertEqual(focusURL("warp://session/\(hex)?a=b"), "")
        XCTAssertEqual(focusURL("warp://session/\(hex)\r\nX-Evil: 1"), "")
        XCTAssertEqual(focusURL("warp://session/\(hex)\n"), "")
    }

    func testRejectsLongSchemeSuffix() {
        XCTAssertEqual(focusURL("warpabcdefghijklm://session/\(hex)"), "")
        XCTAssertEqual(focusURL("warpabcdefghijkl://session/\(hex)"), "warpabcdefghijkl://session/\(hex)")
    }

    func testRejectsSurroundingSpace() {
        XCTAssertEqual(focusURL(" warp://session/\(hex)"), "")
        XCTAssertEqual(focusURL("warp://session/\(hex) "), "")
    }

    func testRejectsEmptyAndMissing() {
        XCTAssertEqual(focusURL(""), "")
        XCTAssertEqual(AgentSourceInfo(headers: [:]).focusURL, "")
    }

    func testIsValidFocusURL() {
        XCTAssertTrue(AgentSourceInfo.isValidFocusURL("warp://session/\(hex)"))
        XCTAssertFalse(AgentSourceInfo.isValidFocusURL(""))
        XCTAssertFalse(AgentSourceInfo.isValidFocusURL("https://evil.example/x"))
        XCTAssertFalse(AgentSourceInfo.isValidFocusURL("warp://session/\(hex)\nX"))
        XCTAssertFalse(AgentSourceInfo.isValidFocusURL("warp://session/\(hex.uppercased())"))
    }

    func testMerge() {
        var base = AgentSourceInfo(terminal: "WarpTerminal", focusURL: "warp://session/\(hex)")
        base.merge(AgentSourceInfo(terminal: "WarpTerminal"))
        XCTAssertEqual(base.focusURL, "warp://session/\(hex)")

        let other = "warppreview://session/ffffffffffffffffffffffffffffffff"
        base.merge(AgentSourceInfo(focusURL: other))
        XCTAssertEqual(base.focusURL, other)
    }

    func testIsEmpty() {
        XCTAssertTrue(AgentSourceInfo().isEmpty)
        XCTAssertFalse(AgentSourceInfo(focusURL: "warp://session/\(hex)").isEmpty)
    }
}
