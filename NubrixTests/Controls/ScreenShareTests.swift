import XCTest
@testable import Nubrix

final class ScreenShareTests: XCTestCase {
    func testStateAndDetail() {
        XCTAssertFalse(ScreenShareState().isShared)
        let watched = ScreenShareState(watched: true)
        XCTAssertTrue(watched.isShared)
        XCTAssertEqual(watched.detail, "Another app can see your screen")
        let mirrored = ScreenShareState(watched: false, mirroringTo: "Living Room TV")
        XCTAssertTrue(mirrored.isShared)
        XCTAssertEqual(mirrored.detail, "Mirroring to Living Room TV")
    }

    func testTrackerAlertsOnlyWhenSharingStartsAfterTheFirstRead() {
        var tracker = ScreenShareTracker()
        XCTAssertNil(tracker.update(ScreenShareState(watched: true), notchHidden: false), "first read is silent")
        XCTAssertNil(tracker.update(ScreenShareState(watched: true), notchHidden: false))
        XCTAssertNil(tracker.update(ScreenShareState(), notchHidden: false))
        let alert = tracker.update(ScreenShareState(watched: true), notchHidden: false)
        XCTAssertEqual(alert?.title, "Screen is shared")
        XCTAssertEqual(alert?.meta, "Notch visible")
        XCTAssertEqual(alert?.tint, .orange)
        XCTAssertEqual(alert?.symbol, "rectangle.on.rectangle")
        XCTAssertEqual(alert?.opensControls, true)
        XCTAssertNil(tracker.update(ScreenShareState(watched: true, mirroringTo: "TV"), notchHidden: false), "already shared")
    }

    func testAlertSaysWhetherTheNotchIsHidden() {
        var tracker = ScreenShareTracker()
        _ = tracker.update(ScreenShareState(), notchHidden: true)
        let alert = tracker.update(ScreenShareState(mirroringTo: "Office TV"), notchHidden: true)
        XCTAssertEqual(alert?.meta, "Notch hidden")
        XCTAssertEqual(alert?.detail, "Mirroring to Office TV")
    }

    func testMirroringToggle() {
        let off = ControlsMirroring.toggle(mirroringTo: nil)
        XCTAssertEqual(off.fill, .neutral)
        XCTAssertEqual(off.label, "Mirroring")
        let on = ControlsMirroring.toggle(mirroringTo: "Living Room TV")
        XCTAssertEqual(on.fill, .accent)
        XCTAssertTrue(on.help.contains("Living Room TV"))
    }
}
