import XCTest
@testable import Nubrix

final class WhatsNewTests: XCTestCase {
    func testFreshInstallNeverShows() {
        XCTAssertFalse(WhatsNewPolicy.shouldShow(currentVersion: "0.5.0", lastSeenVersion: nil, isFirstLaunch: true, hasNotes: true))
    }

    func testUpgradeWithNotesShows() {
        XCTAssertTrue(WhatsNewPolicy.shouldShow(currentVersion: "0.5.0", lastSeenVersion: "0.4.0", isFirstLaunch: false, hasNotes: true))
    }

    func testSameVersionDoesNotShowAgain() {
        XCTAssertFalse(WhatsNewPolicy.shouldShow(currentVersion: "0.5.0", lastSeenVersion: "0.5.0", isFirstLaunch: false, hasNotes: true))
    }

    func testUpgradeWithoutNotesDoesNotShow() {
        XCTAssertFalse(WhatsNewPolicy.shouldShow(currentVersion: "0.5.1", lastSeenVersion: "0.5.0", isFirstLaunch: false, hasNotes: false))
    }

    func testExistingUserWithNilLastSeenShows() {
        XCTAssertTrue(WhatsNewPolicy.shouldShow(currentVersion: "0.5.0", lastSeenVersion: nil, isFirstLaunch: false, hasNotes: true))
    }

    func testCatalogHasFiveOhEntry() throws {
        let notes = try XCTUnwrap(WhatsNewCatalog.notes(for: "0.5.0"))
        XCTAssertFalse(notes.title.isEmpty)
        XCTAssertEqual(notes.items.count, 4)
        XCTAssertEqual(notes.actionTab, .theme)
    }

    func testSkippedVersionStillGetsLatestNotes() {
        let notes = WhatsNewCatalog.latestNotes(upTo: "0.5.1", after: "0.4.0")
        XCTAssertEqual(notes?.title, "What's new in Nubrix 0.5.0")
    }

    func testAlreadySeenNotesAreNotRepeated() {
        XCTAssertNil(WhatsNewCatalog.latestNotes(upTo: "0.5.1", after: "0.5.0"))
    }

    func testExistingUserWithoutRecordGetsNotesUpToCurrent() {
        XCTAssertNotNil(WhatsNewCatalog.latestNotes(upTo: "0.5.1", after: nil))
        XCTAssertNil(WhatsNewCatalog.latestNotes(upTo: "0.4.0", after: nil))
    }

    func testVersionCompareIsNumeric() {
        XCTAssertEqual(WhatsNewCatalog.compare("0.10.0", "0.9.1"), .orderedDescending)
        XCTAssertEqual(WhatsNewCatalog.compare("0.5", "0.5.0"), .orderedSame)
        XCTAssertEqual(WhatsNewCatalog.compare("0.5.0", "0.5.1"), .orderedAscending)
    }
}
