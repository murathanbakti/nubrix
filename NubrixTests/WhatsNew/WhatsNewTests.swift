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

    func testCatalogHasMouseEntryForSixOh() throws {
        let notes = try XCTUnwrap(WhatsNewCatalog.notes(for: "0.6.0"))
        XCTAssertEqual(notes.title, "What's new in Nubrix 0.6.0")
        XCTAssertEqual(notes.items.count, 3)
        XCTAssertEqual(notes.actionTab, .mouse)
        XCTAssertEqual(notes.actionTitle, "Open Mouse Settings")
    }

    func testUpdatingToSixOhShowsTheMouseNotes() {
        XCTAssertEqual(WhatsNewCatalog.latestNotes(upTo: "0.6.0", after: "0.5.5")?.actionTab, .mouse)
        XCTAssertEqual(WhatsNewCatalog.latestNotes(upTo: "0.6.0", after: "0.4.0")?.actionTab, .mouse)
        XCTAssertNil(WhatsNewCatalog.latestNotes(upTo: "0.6.0", after: "0.6.0"))
    }

    func testFiveFiveStillGetsTheThemeNotes() {
        XCTAssertEqual(WhatsNewCatalog.latestNotes(upTo: "0.5.5", after: "0.4.0")?.actionTab, .theme)
    }

    func testEveryNoteHasExistingSymbolsAndUniqueTitles() {
        for (version, notes) in WhatsNewCatalog.notes {
            XCTAssertTrue(notes.title.contains(version), version)
            let titles = notes.items.map(\.title)
            XCTAssertEqual(Set(titles).count, titles.count, version)
            for item in notes.items {
                XCTAssertFalse(item.body.isEmpty, "\(version) \(item.title)")
                XCTAssertNotNil(NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil), "\(version) \(item.symbol)")
            }
            XCTAssertEqual(notes.actionTab == nil, notes.actionTitle == nil, version)
        }
    }

    func testVersionCompareIsNumeric() {
        XCTAssertEqual(WhatsNewCatalog.compare("0.10.0", "0.9.1"), .orderedDescending)
        XCTAssertEqual(WhatsNewCatalog.compare("0.5", "0.5.0"), .orderedSame)
        XCTAssertEqual(WhatsNewCatalog.compare("0.5.0", "0.5.1"), .orderedAscending)
    }
}
