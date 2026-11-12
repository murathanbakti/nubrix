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
}
