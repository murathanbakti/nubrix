import XCTest
@testable import Nubrix

final class DockBadgeAppListTests: XCTestCase {
    func testDedupesUnion() {
        let rows = DockBadgeAppList.rows(known: ["a", "b"], allowed: ["b", "c"], running: ["c", "d", "a"],
                                         defaults: [], ownBundleID: nil, isInstalled: { _ in false })
        XCTAssertEqual(rows, ["a", "b", "c", "d"])
    }

    func testAllowedKeptWhenNotInstalled() {
        let rows = DockBadgeAppList.rows(known: [], allowed: ["gone.app"], running: [],
                                         defaults: [], ownBundleID: nil, isInstalled: { _ in false })
        XCTAssertEqual(rows, ["gone.app"])
    }

    func testDefaultsOnlyWhenInstalled() {
        let rows = DockBadgeAppList.rows(known: [], allowed: [], running: [],
                                         defaults: ["installed", "missing"], ownBundleID: nil,
                                         isInstalled: { $0 == "installed" })
        XCTAssertEqual(rows, ["installed"])
    }

    func testBuiltInDefaultsFilteredByInstalled() {
        let rows = DockBadgeAppList.rows(known: [], allowed: [], running: [], ownBundleID: nil,
                                         isInstalled: { $0 == "com.apple.mail" })
        XCTAssertEqual(rows, ["com.apple.mail"])
        XCTAssertTrue(DockBadgeAppList.defaults.contains("com.apple.MobileSMS"))
    }

    func testOwnBundleIDRemoved() {
        let rows = DockBadgeAppList.rows(known: ["me"], allowed: ["me"], running: ["me", "other"],
                                         defaults: ["me"], ownBundleID: "me", isInstalled: { _ in true })
        XCTAssertEqual(rows, ["other"])
    }

    func testEmptyStringsRemoved() {
        let rows = DockBadgeAppList.rows(known: [""], allowed: ["", "a"], running: [""],
                                         defaults: [""], ownBundleID: nil, isInstalled: { _ in true })
        XCTAssertEqual(rows, ["a"])
    }

    func testEmptyInputs() {
        let rows = DockBadgeAppList.rows(known: [], allowed: [], running: [], defaults: [],
                                         ownBundleID: nil, isInstalled: { _ in true })
        XCTAssertEqual(rows, [])
    }

    func testSortedByBundleID() {
        let rows = DockBadgeAppList.rows(known: ["z"], allowed: ["m"], running: ["a"], defaults: [],
                                         ownBundleID: nil, isInstalled: { _ in true })
        XCTAssertEqual(rows, ["a", "m", "z"])
    }
}
