import XCTest
@testable import Nubrix

final class DockBadgeSummaryTests: XCTestCase {
    private func badge(_ id: String, _ count: Int?) -> DockBadge {
        DockBadge(bundleID: id, label: count.map(String.init) ?? "•", count: count)
    }

    func testTotalCountsDotBadgesAsOne() {
        let summary = DockBadgeSummary(badges: [badge("a", 3), badge("b", nil), badge("c", 5)], order: ["a", "b", "c"])
        XCTAssertEqual(summary.total, 9)
        XCTAssertEqual(summary.totalText, "9")
        XCTAssertFalse(summary.isEmpty)
    }

    func testTopIsHighestCount() {
        let summary = DockBadgeSummary(badges: [badge("a", 3), badge("b", 8), badge("c", nil)], order: ["a", "b", "c"])
        XCTAssertEqual(summary.top?.bundleID, "b")
        XCTAssertEqual(summary.badges.map(\.bundleID), ["b", "a", "c"])
    }

    func testTieIsBrokenByChosenOrder() {
        let badges = [badge("a", 2), badge("b", 2), badge("c", 2)]
        let summary = DockBadgeSummary(badges: badges, order: ["c", "a", "b"])
        XCTAssertEqual(summary.badges.map(\.bundleID), ["c", "a", "b"])
    }

    func testUnknownAppsSortAfterKnownThenByBundleID() {
        let badges = [badge("z", 1), badge("y", 1), badge("known", 1)]
        let summary = DockBadgeSummary(badges: badges, order: ["known"])
        XCTAssertEqual(summary.badges.map(\.bundleID), ["known", "y", "z"])
    }

    func testDotBadgeTiesWithOne() {
        let summary = DockBadgeSummary(badges: [badge("a", nil), badge("b", 1)], order: ["b", "a"])
        XCTAssertEqual(summary.top?.bundleID, "b")
    }

    func testEmptySummary() {
        let summary = DockBadgeSummary.empty
        XCTAssertEqual(summary.total, 0)
        XCTAssertEqual(summary.totalText, "")
        XCTAssertNil(summary.top)
        XCTAssertTrue(summary.isEmpty)
    }

    func testTotalTextCapsAboveNinetyNine() {
        XCTAssertEqual(DockBadgeSummary(badges: [badge("a", 99)], order: []).totalText, "99")
        XCTAssertEqual(DockBadgeSummary(badges: [badge("a", 100)], order: []).totalText, "99+")
        XCTAssertEqual(DockBadgeSummary(badges: [badge("a", 60), badge("b", 50)], order: []).totalText, "99+")
    }

    func testBadgeLookup() {
        let summary = DockBadgeSummary(badges: [badge("a", 3), badge("b", nil)], order: ["a", "b"])
        XCTAssertEqual(summary.badge(for: "a")?.count, 3)
        XCTAssertNil(summary.badge(for: "b")?.count)
        XCTAssertNotNil(summary.badge(for: "b"))
        XCTAssertNil(summary.badge(for: "missing"))
    }

    func testWeightAndIdentity() {
        XCTAssertEqual(badge("a", 4).weight, 4)
        XCTAssertEqual(badge("a", nil).weight, 1)
        XCTAssertEqual(badge("a", 4).id, "a")
    }
}
