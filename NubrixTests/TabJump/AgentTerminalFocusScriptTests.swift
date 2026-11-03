import Carbon
import XCTest
@testable import Nubrix

final class AgentTerminalFocusScriptTests: XCTestCase {
    private let injection = #"/tmp/a" & (do shell script "touch /tmp/pwn") & ""#

    func testGhosttySourceIgnoresInputs() {
        let source = AgentSourceInfo(appBundleID: "com.mitchellh.ghostty", terminal: "ghostty", tty: "ttys016")
        guard case .script(let script) = AgentTerminalFocus.strategy(source: source, cwd: injection, ghosttyVersion: "1.4.0") else {
            return XCTFail("expected script")
        }
        XCTAssertEqual(script.source, AgentTerminalFocus.ghosttySource)
        XCTAssertFalse(script.source.contains("pwn"))
        XCTAssertFalse(script.source.contains("ttys016"))
        XCTAssertEqual(script.arguments, ["/dev/ttys016", injection])
    }

    func testTerminalAndITermSourcesContainDevice() {
        XCTAssertTrue(AgentTerminalFocus.terminalScript(device: "/dev/ttys016")?.contains(#""/dev/ttys016""#) == true)
        XCTAssertTrue(AgentTerminalFocus.iTermScript(device: "/dev/ttys016")?.contains(#""/dev/ttys016""#) == true)
    }

    func testScriptBuildersRejectInvalidDevice() {
        for device in ["", "ttys016", "/dev/ttys", #"/dev/ttys1" & (do shell script "x") & ""#, "/dev/ttys12345"] {
            XCTAssertNil(AgentTerminalFocus.terminalScript(device: device), device)
            XCTAssertNil(AgentTerminalFocus.iTermScript(device: device), device)
        }
    }

    func testSubroutineEventShape() {
        let event = AgentTerminalFocus.subroutineEvent(handler: "Nubrix_Focus", arguments: ["/dev/ttys016", "", "/Users/a b"])
        XCTAssertEqual(event.eventClass, AEEventClass(kASAppleScriptSuite))
        XCTAssertEqual(event.eventID, AEEventID(kASSubroutineEvent))
        XCTAssertEqual(event.eventClass, 0x61736372)
        XCTAssertEqual(event.eventID, 0x70736272)
        XCTAssertEqual(event.paramDescriptor(forKeyword: AEKeyword(keyASSubroutineName))?.stringValue, "nubrix_focus")

        let list = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))
        XCTAssertEqual(list?.numberOfItems, 3)
        XCTAssertEqual(list?.atIndex(1)?.stringValue, "/dev/ttys016")
        XCTAssertEqual(list?.atIndex(2)?.stringValue, "")
        XCTAssertEqual(list?.atIndex(3)?.stringValue, "/Users/a b")
    }

    func testSubroutineEventWithoutArguments() {
        let event = AgentTerminalFocus.subroutineEvent(handler: "nubrix_focus", arguments: [])
        XCTAssertEqual(event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.numberOfItems, 0)
    }

    func testRunReturnsArgumentsVerbatim() async throws {
        let first = #"" & (do shell script "echo pwned") & ""#
        let second = "line1\nline2 \\ \"quoted\""
        let script = AgentTerminalFocus.Script(
            bundleID: "x",
            source: "on nubrix_echo(a, b)\n return a & \"|\" & b\nend nubrix_echo",
            handler: "nubrix_echo",
            arguments: [first, second]
        )
        let descriptor = try await AgentTerminalFocus.runDescriptor(script)
        XCTAssertEqual(descriptor.stringValue, first + "|" + second)
    }

    func testRunBooleanHandler() async throws {
        let source = "on nubrix_is(a, b)\n return a is b\nend nubrix_is"
        let same = AgentTerminalFocus.Script(bundleID: "x", source: source, handler: "nubrix_is", arguments: ["/a/b", "/a/b"])
        let different = AgentTerminalFocus.Script(bundleID: "x", source: source, handler: "nubrix_is", arguments: ["/a/b", "/a/c"])
        let sameResult = try await AgentTerminalFocus.run(same)
        let differentResult = try await AgentTerminalFocus.run(different)
        XCTAssertTrue(sameResult)
        XCTAssertFalse(differentResult)
    }

    func testRunPlainScript() async throws {
        let script = AgentTerminalFocus.Script(bundleID: "x", source: "return true", handler: nil, arguments: [])
        let result = try await AgentTerminalFocus.run(script)
        XCTAssertTrue(result)
    }

    func testRunThrowsOnInvalidScript() async {
        let script = AgentTerminalFocus.Script(bundleID: "x", source: "this is not ( applescript", handler: "nubrix_x", arguments: [])
        do {
            _ = try await AgentTerminalFocus.run(script)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual((error as NSError).domain, "AppleScriptError")
        }
    }
}
