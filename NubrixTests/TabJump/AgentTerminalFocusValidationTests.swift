import XCTest
@testable import Nubrix

final class AgentTerminalFocusValidationTests: XCTestCase {
    func testTTYDeviceAcceptsValid() {
        XCTAssertEqual(AgentTerminalFocus.ttyDevice("ttys016"), "/dev/ttys016")
        XCTAssertEqual(AgentTerminalFocus.ttyDevice("ttys1234"), "/dev/ttys1234")
    }

    func testTTYDeviceRejectsInvalid() {
        let invalid = [
            "", "ttys", "tty016", "ttys1;", "ttys12345", "/dev/ttys1", "ttys\u{0661}\u{0662}",
            "ttys1\n", " ttys1", "ttys1 ",
            "ttys1\" & do shell script \"touch /tmp/x",
        ]
        for tty in invalid {
            XCTAssertNil(AgentTerminalFocus.ttyDevice(tty), tty)
        }
    }

    func testDirectoryAccepts() {
        XCTAssertEqual(AgentTerminalFocus.directory("/Users/a/b c"), "/Users/a/b c")
        XCTAssertEqual(AgentTerminalFocus.directory("/"), "/")
    }

    func testDirectoryRejects() {
        XCTAssertNil(AgentTerminalFocus.directory(nil))
        XCTAssertNil(AgentTerminalFocus.directory(""))
        XCTAssertNil(AgentTerminalFocus.directory("relative/path"))
        XCTAssertNil(AgentTerminalFocus.directory("~/code"))
        XCTAssertNil(AgentTerminalFocus.directory("/a\nb"))
        XCTAssertNil(AgentTerminalFocus.directory("/a\tb"))
        XCTAssertNil(AgentTerminalFocus.directory("/a\u{7F}b"))
        XCTAssertNil(AgentTerminalFocus.directory("/" + String(repeating: "a", count: 1024)))
        XCTAssertNotNil(AgentTerminalFocus.directory("/" + String(repeating: "a", count: 1023)))
    }

    func testIsWarpHandler() {
        XCTAssertTrue(AgentTerminalFocus.isWarpHandler(bundleID: "dev.warp.Warp-Stable"))
        XCTAssertTrue(AgentTerminalFocus.isWarpHandler(bundleID: "dev.warp.Warp-Preview"))
        XCTAssertFalse(AgentTerminalFocus.isWarpHandler(bundleID: nil))
        XCTAssertFalse(AgentTerminalFocus.isWarpHandler(bundleID: "dev.warpx.x"))
        XCTAssertFalse(AgentTerminalFocus.isWarpHandler(bundleID: "com.evil.dev.warp.x"))
        XCTAssertFalse(AgentTerminalFocus.isWarpHandler(bundleID: ""))
    }

    func testGhosttySupport() {
        XCTAssertEqual(AgentTerminalFocus.ghosttySupport(version: "1.4.0"), .ttyAndDirectory)
        XCTAssertEqual(AgentTerminalFocus.ghosttySupport(version: "1.4.0-dev+abc"), .ttyAndDirectory)
        XCTAssertEqual(AgentTerminalFocus.ghosttySupport(version: "1.10.0"), .ttyAndDirectory)
        XCTAssertEqual(AgentTerminalFocus.ghosttySupport(version: "2.0.0"), .ttyAndDirectory)
        XCTAssertEqual(AgentTerminalFocus.ghosttySupport(version: "1.3"), .directoryOnly)
        XCTAssertEqual(AgentTerminalFocus.ghosttySupport(version: "1.3.1"), .directoryOnly)
        XCTAssertEqual(AgentTerminalFocus.ghosttySupport(version: "1.2.3"), .none)
        XCTAssertEqual(AgentTerminalFocus.ghosttySupport(version: "0.9"), .none)
        XCTAssertEqual(AgentTerminalFocus.ghosttySupport(version: nil), .ttyAndDirectory)
        XCTAssertEqual(AgentTerminalFocus.ghosttySupport(version: "garbage"), .ttyAndDirectory)
        XCTAssertEqual(AgentTerminalFocus.ghosttySupport(version: ""), .ttyAndDirectory)
    }

    func testIsWarp() {
        XCTAssertTrue(AgentTerminalFocus.isWarp(bundleID: "dev.warp.Warp-Stable", terminal: ""))
        XCTAssertTrue(AgentTerminalFocus.isWarp(bundleID: nil, terminal: "WarpTerminal"))
        XCTAssertFalse(AgentTerminalFocus.isWarp(bundleID: "com.mitchellh.ghostty", terminal: "ghostty"))
        XCTAssertFalse(AgentTerminalFocus.isWarp(bundleID: nil, terminal: ""))
    }
}
