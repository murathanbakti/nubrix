import XCTest
@testable import Nubrix

final class DisplayReconfigurationTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testQuietBeforeAnyEvent() {
        let gate = DisplayReconfigurationGate()
        XCTAssertTrue(gate.isQuiet(at: t0))
        XCTAssertEqual(gate.timeUntilQuiet(at: t0), 0)
        XCTAssertEqual(gate.delayBeforeRefresh(at: t0), DisplayReconfigurationGate.debounce)
    }

    func testBusyFromBeginUntilSettled() {
        var gate = DisplayReconfigurationGate()
        XCTAssertTrue(gate.record(flags: .beginConfigurationFlag, at: t0), "first event starts an episode")
        XCTAssertFalse(gate.isQuiet(at: t0.addingTimeInterval(4)), "still in progress until the cap")
        XCTAssertFalse(gate.record(flags: [.addFlag, .mirrorFlag], at: t0.addingTimeInterval(0.2)))
        XCTAssertFalse(gate.isQuiet(at: t0.addingTimeInterval(0.5)))
        XCTAssertFalse(gate.isQuiet(at: t0.addingTimeInterval(1.1)), "1 s after the last event is 0.9 s here")
        XCTAssertTrue(gate.isQuiet(at: t0.addingTimeInterval(1.21)))
    }

    func testEachEventRestartsTheSettleTime() {
        var gate = DisplayReconfigurationGate()
        gate.record(flags: .beginConfigurationFlag, at: t0)
        gate.record(flags: .movedFlag, at: t0.addingTimeInterval(0.1))
        gate.record(flags: .beginConfigurationFlag, at: t0.addingTimeInterval(0.8))
        gate.record(flags: .setModeFlag, at: t0.addingTimeInterval(0.9))
        XCTAssertFalse(gate.isQuiet(at: t0.addingTimeInterval(1.5)))
        XCTAssertEqual(gate.timeUntilQuiet(at: t0.addingTimeInterval(1.4)), 0.5, accuracy: 0.001)
        XCTAssertTrue(gate.isQuiet(at: t0.addingTimeInterval(1.95)))
    }

    func testRefreshDelayIsDebounceOrSettleWhicheverIsLonger() {
        var gate = DisplayReconfigurationGate()
        gate.record(flags: .beginConfigurationFlag, at: t0)
        XCTAssertEqual(gate.delayBeforeRefresh(at: t0), DisplayReconfigurationGate.settle)
        gate.record(flags: .setModeFlag, at: t0.addingTimeInterval(0.1))
        XCTAssertEqual(gate.delayBeforeRefresh(at: t0.addingTimeInterval(0.8)), 0.3, accuracy: 0.001)
        XCTAssertEqual(gate.delayBeforeRefresh(at: t0.addingTimeInterval(5)), DisplayReconfigurationGate.debounce)
    }

    func testBeginWithoutEndSettlesAfterTheCap() {
        var gate = DisplayReconfigurationGate()
        gate.record(flags: .beginConfigurationFlag, at: t0)
        XCTAssertFalse(gate.isQuiet(at: t0.addingTimeInterval(4.9)))
        XCTAssertEqual(gate.timeUntilQuiet(at: t0.addingTimeInterval(4.5)), 0.5, accuracy: 0.001)
        XCTAssertTrue(gate.isQuiet(at: t0.addingTimeInterval(5.01)))
        XCTAssertEqual(gate.timeUntilQuiet(at: t0.addingTimeInterval(6)), 0)
    }

    func testNewEpisodeAfterSettling() {
        var gate = DisplayReconfigurationGate()
        gate.record(flags: .beginConfigurationFlag, at: t0)
        gate.record(flags: .setModeFlag, at: t0.addingTimeInterval(0.1))
        XCTAssertTrue(gate.record(flags: .beginConfigurationFlag, at: t0.addingTimeInterval(10)))
    }

    func testMirrorsOfAnotherDisplayGetNoWindow() {
        XCTAssertTrue(NotchScreenFilter.hostsNotch(mirrorsDisplay: kCGNullDirectDisplay))
        XCTAssertFalse(NotchScreenFilter.hostsNotch(mirrorsDisplay: 1))
        let screens: [(uuid: String, mirrorsDisplay: CGDirectDisplayID)] = [("A", kCGNullDirectDisplay), ("B", 7), ("C", kCGNullDirectDisplay)]
        XCTAssertEqual(NotchScreenFilter.eligible(screens), ["A", "C"])
        XCTAssertEqual(NotchScreenFilter.eligible([]), [])
    }
}
