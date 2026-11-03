import XCTest
@testable import Nubrix

final class AgentTerminalFocusStrategyTests: XCTestCase {
    private let hex = "0123456789abcdef0123456789abcdef"
    private let cwd = "/Users/me/project"

    private func script(_ strategy: AgentTerminalFocus.Strategy, file: StaticString = #filePath, line: UInt = #line) -> AgentTerminalFocus.Script? {
        guard case .script(let script) = strategy else {
            XCTFail("expected script, got \(strategy)", file: file, line: line)
            return nil
        }
        return script
    }

    private func ghosttySource(tty: String = "ttys016", terminal: String = "ghostty", appBundleID: String = "com.mitchellh.ghostty") -> AgentSourceInfo {
        AgentSourceInfo(appBundleID: appBundleID, terminal: terminal, tty: tty)
    }

    func testTerminalWithTTY() {
        let source = AgentSourceInfo(appBundleID: "com.apple.Terminal", terminal: "Apple_Terminal", tty: "ttys016")
        let result = script(AgentTerminalFocus.strategy(source: source, cwd: cwd, ghosttyVersion: nil))
        XCTAssertEqual(result?.bundleID, AgentTerminalFocus.terminal)
        XCTAssertNil(result?.handler)
        XCTAssertEqual(result?.arguments, [])
        XCTAssertEqual(result?.source, AgentTerminalFocus.terminalScript(device: "/dev/ttys016"))
    }

    func testTerminalWithoutTTY() {
        let source = AgentSourceInfo(appBundleID: "com.apple.Terminal", terminal: "Apple_Terminal")
        XCTAssertEqual(AgentTerminalFocus.strategy(source: source, cwd: cwd, ghosttyVersion: nil), .activate)
    }

    func testITermWithTTY() {
        let source = AgentSourceInfo(terminal: "iTerm.app", tty: "ttys003")
        let result = script(AgentTerminalFocus.strategy(source: source, cwd: cwd, ghosttyVersion: nil))
        XCTAssertEqual(result?.bundleID, AgentTerminalFocus.iTerm)
        XCTAssertEqual(result?.source, AgentTerminalFocus.iTermScript(device: "/dev/ttys003"))
    }

    func testITermWithoutTTY() {
        let source = AgentSourceInfo(terminal: "iTerm.app")
        XCTAssertEqual(AgentTerminalFocus.strategy(source: source, cwd: cwd, ghosttyVersion: nil), .activate)
    }

    func testGhosttyTTYAndDirectoryVersions() {
        for version in ["1.4.0", "1.5.2", "2.0.0", nil, "garbage", "1.4.0-dev+abc"] {
            let result = script(AgentTerminalFocus.strategy(source: ghosttySource(), cwd: cwd, ghosttyVersion: version))
            XCTAssertEqual(result?.bundleID, AgentTerminalFocus.ghostty, version ?? "nil")
            XCTAssertEqual(result?.handler, "nubrix_focus", version ?? "nil")
            XCTAssertEqual(result?.arguments, ["/dev/ttys016", cwd], version ?? "nil")
            XCTAssertEqual(result?.source, AgentTerminalFocus.ghosttySource, version ?? "nil")
        }
    }

    func testGhosttyDirectoryOnlyVersions() {
        for version in ["1.3.0", "1.3.1"] {
            let result = script(AgentTerminalFocus.strategy(source: ghosttySource(), cwd: cwd, ghosttyVersion: version))
            XCTAssertEqual(result?.arguments, ["", cwd], version)
        }
    }

    func testGhosttyTooOld() {
        XCTAssertEqual(AgentTerminalFocus.strategy(source: ghosttySource(), cwd: cwd, ghosttyVersion: "1.2.3"), .activate)
    }

    func testGhosttyWithTTYButNoCwd() {
        let result = script(AgentTerminalFocus.strategy(source: ghosttySource(), cwd: nil, ghosttyVersion: "1.4.0"))
        XCTAssertEqual(result?.arguments, ["/dev/ttys016", ""])
    }

    func testGhosttyDirectoryOnlyWithoutCwd() {
        XCTAssertEqual(AgentTerminalFocus.strategy(source: ghosttySource(), cwd: nil, ghosttyVersion: "1.3.0"), .activate)
    }

    func testGhosttyRelativeCwdWithoutTTY() {
        XCTAssertEqual(AgentTerminalFocus.strategy(source: ghosttySource(tty: ""), cwd: "relative/dir", ghosttyVersion: "1.4.0"), .activate)
    }

    func testGhosttyNoTTYUsesDirectory() {
        let result = script(AgentTerminalFocus.strategy(source: ghosttySource(tty: ""), cwd: cwd, ghosttyVersion: "1.4.0"))
        XCTAssertEqual(result?.arguments, ["", cwd])
    }

    func testBundleFromTermProgramGhostty() {
        let source = AgentSourceInfo(terminal: "ghostty", tty: "ttys016")
        let result = script(AgentTerminalFocus.strategy(source: source, cwd: cwd, ghosttyVersion: "1.4.0"))
        XCTAssertEqual(result?.bundleID, AgentTerminalFocus.ghostty)
    }

    func testBundleFromTermProgramWarp() {
        let url = "warp://session/\(hex)"
        let source = AgentSourceInfo(terminal: "WarpTerminal", focusURL: url)
        XCTAssertEqual(AgentTerminalFocus.bundleID(for: source), AgentTerminalFocus.warpStable)
        XCTAssertEqual(AgentTerminalFocus.strategy(source: source, cwd: cwd, ghosttyVersion: nil), .warp(URL(string: url)!))
    }

    func testWarpWithFocusURL() {
        let url = "warppreview://session/\(hex)"
        let source = AgentSourceInfo(appBundleID: "dev.warp.Warp-Preview", terminal: "WarpTerminal", focusURL: url)
        XCTAssertEqual(AgentTerminalFocus.strategy(source: source, cwd: cwd, ghosttyVersion: nil), .warp(URL(string: url)!))
    }

    func testWarpIgnoresInvalidFocusURLSetAfterInit() {
        for value in ["https://evil.example/x", "warp://session/\(hex)\nX"] {
            var source = AgentSourceInfo(terminal: "WarpTerminal")
            source.focusURL = value
            XCTAssertEqual(AgentTerminalFocus.strategy(source: source, cwd: cwd, ghosttyVersion: nil), .activate, value)
        }
    }

    func testWarpWithoutFocusURL() {
        let source = AgentSourceInfo(appBundleID: "dev.warp.Warp-Stable", terminal: "WarpTerminal", tty: "ttys016")
        XCTAssertEqual(AgentTerminalFocus.strategy(source: source, cwd: cwd, ghosttyVersion: nil), .activate)
    }

    func testDesktopWithHostSession() {
        let source = AgentSourceInfo(entrypoint: "claude-desktop", hostSessionID: "local_abc-123")
        let expected = AgentTerminalFocus.desktopURL(sessionID: "local_abc-123")!
        XCTAssertEqual(AgentTerminalFocus.strategy(source: source, cwd: cwd, ghosttyVersion: nil), .desktop(expected))
        XCTAssertEqual(expected.absoluteString, "claude://code/continue?session=local_abc-123")
    }

    func testDesktopByBundleID() {
        let source = AgentSourceInfo(appBundleID: AgentSourceInfo.desktopBundleID, hostSessionID: "local_abc")
        guard case .desktop = AgentTerminalFocus.strategy(source: source, cwd: nil, ghosttyVersion: nil) else {
            return XCTFail("expected desktop")
        }
    }

    func testDesktopWithoutHostSessionActivates() {
        let source = AgentSourceInfo(entrypoint: "claude-desktop")
        XCTAssertEqual(AgentTerminalFocus.strategy(source: source, cwd: cwd, ghosttyVersion: nil), .activate)
    }

    func testUnknownAppActivates() {
        let source = AgentSourceInfo(entrypoint: "claude-vscode", appBundleID: "com.microsoft.VSCode", terminal: "vscode", tty: "ttys016")
        XCTAssertEqual(AgentTerminalFocus.strategy(source: source, cwd: cwd, ghosttyVersion: "1.4.0"), .activate)
    }

    func testEmptySourceActivates() {
        XCTAssertEqual(AgentTerminalFocus.strategy(source: AgentSourceInfo(), cwd: cwd, ghosttyVersion: nil), .activate)
    }
}
