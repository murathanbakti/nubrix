import XCTest
@testable import Nubrix

final class UpdateReminderTests: XCTestCase {
    private func scheduled(_ version: String = "0.2.1", ready: Bool = false) -> UpdateReminderEvent {
        .willShow(handledBySparkle: false, userInitiated: false, version: version, readyToInstall: ready)
    }

    func testScheduledUpdateNotShownBySparkleCreatesAReminder() {
        XCTAssertEqual(UpdateReminderLogic.reduce(nil, scheduled()), UpdateReminder(version: "0.2.1", readyToInstall: false))
    }

    func testDownloadedUpdateReadsAsReadyToInstall() {
        XCTAssertEqual(UpdateReminderLogic.reduce(nil, scheduled(ready: true)), UpdateReminder(version: "0.2.1", readyToInstall: true))
    }

    func testUserInitiatedChecksNeverCreateAReminder() {
        let event = UpdateReminderEvent.willShow(handledBySparkle: false, userInitiated: true, version: "0.2.1", readyToInstall: false)
        XCTAssertNil(UpdateReminderLogic.reduce(nil, event))
    }

    func testUpdatesSparkleShowsItselfLeaveTheReminderAlone() {
        let event = UpdateReminderEvent.willShow(handledBySparkle: true, userInitiated: false, version: "0.2.1", readyToInstall: false)
        XCTAssertNil(UpdateReminderLogic.reduce(nil, event))
        let existing = UpdateReminder(version: "0.2.0", readyToInstall: false)
        XCTAssertEqual(UpdateReminderLogic.reduce(existing, event), existing)
        let initiated = UpdateReminderEvent.willShow(handledBySparkle: false, userInitiated: true, version: "0.2.2", readyToInstall: true)
        XCTAssertEqual(UpdateReminderLogic.reduce(existing, initiated), existing)
    }

    func testAttentionAndSessionEndClearIt() {
        let existing = UpdateReminder(version: "0.2.1", readyToInstall: false)
        XCTAssertNil(UpdateReminderLogic.reduce(existing, .attention))
        XCTAssertNil(UpdateReminderLogic.reduce(existing, .sessionFinished))
        XCTAssertNil(UpdateReminderLogic.reduce(nil, .attention))
    }

    func testANewerScheduledUpdateReplacesTheReminder() {
        let existing = UpdateReminder(version: "0.2.1", readyToInstall: false)
        XCTAssertEqual(UpdateReminderLogic.reduce(existing, scheduled("0.2.2", ready: true)), UpdateReminder(version: "0.2.2", readyToInstall: true))
    }
}
