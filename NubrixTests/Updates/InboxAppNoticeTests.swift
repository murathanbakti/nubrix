import XCTest
@testable import Nubrix

final class InboxAppNoticeTests: XCTestCase {
    func testRecordAppAddsANubrixNotice() {
        var ledger = InboxLedger()
        XCTAssertTrue(ledger.recordApp(key: "update", title: "Nubrix 0.2.1 is available", message: "m"))
        XCTAssertEqual(ledger.unreadCount, 1)
        XCTAssertEqual(ledger.unreadCount(for: .nubrix), 1)
        XCTAssertEqual(ledger.newest?.source, .nubrix)
        XCTAssertEqual(ledger.newest?.severity, .notice)
        XCTAssertEqual(ledger.newest?.key, "update")
    }

    func testRecordAppReplacesTheEntryWithTheSameKey() {
        var ledger = InboxLedger()
        ledger.recordApp(key: "update", title: "old", message: "m")
        ledger.recordApp(key: "hooks", title: "hooks", message: "m")
        ledger.recordApp(key: "update", title: "new", message: "m")
        XCTAssertEqual(ledger.entries.count, 2)
        XCTAssertEqual(ledger.entries.first?.title, "new")
        XCTAssertEqual(ledger.entries.filter { $0.key == "update" }.count, 1)
    }

    func testClearAppRemovesOnlyThatKey() {
        var ledger = InboxLedger()
        ledger.recordApp(key: "update", title: "u", message: "m")
        ledger.recordApp(key: "hooks", title: "h", message: "m")
        ledger.recordNotice(title: "n", message: "m")
        XCTAssertTrue(ledger.clearApp(key: "update"))
        XCTAssertFalse(ledger.clearApp(key: "update"))
        XCTAssertEqual(ledger.entries.map(\.title), ["n", "h"])
    }

    func testAppNoticesDoNotTouchOtherSourcesWithTheSameKey() {
        var ledger = InboxLedger()
        ledger.recordGitHub(key: "update", severity: .notice, title: "g", message: "m")
        ledger.recordApp(key: "update", title: "u", message: "m")
        XCTAssertEqual(ledger.unreadCount(for: .github), 1)
        XCTAssertEqual(ledger.unreadCount(for: .nubrix), 1)
        ledger.clearApp(key: "update")
        XCTAssertEqual(ledger.unreadCount(for: .github), 1)
    }

    func testNubrixSourceMapsToTheHomeTab() {
        XCTAssertEqual(InboxSource.nubrix.targetTab, .home)
        XCTAssertEqual(InboxSource.sources(for: .home), [.nubrix])
        XCTAssertEqual(InboxSource.nubrix.title, "Nubrix")
    }

    func testMarkingTheNubrixSourceReadClearsIt() {
        var ledger = InboxLedger()
        ledger.recordApp(key: "update", title: "u", message: "m")
        XCTAssertTrue(ledger.markRead(source: .nubrix))
        XCTAssertEqual(ledger.unreadCount, 0)
    }
}
