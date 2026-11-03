import XCTest
@testable import Nubrix

final class SettingsTabTests: XCTestCase {
    func testSidebarOrderFollowsGroups() {
        XCTAssertEqual(SettingsTab.allCases, [
            .general, .appearance, .permissions,
            .claudeCode, .github, .dev,
            .tabs, .notifications, .vitrin, .media, .calendar, .shelf, .huds,
            .shortcuts, .advanced, .about
        ])
    }

    func testGroupsHoldTheirTabsInOrder() {
        XCTAssertEqual(SettingsTabGroup.main.tabs, [.general, .appearance, .permissions])
        XCTAssertEqual(SettingsTabGroup.developer.tabs, [.claudeCode, .github, .dev])
        XCTAssertEqual(SettingsTabGroup.notch.tabs, [.tabs, .notifications, .vitrin, .media, .calendar, .shelf, .huds])
        XCTAssertEqual(SettingsTabGroup.app.tabs, [.shortcuts, .advanced, .about])
    }

    func testGroupHeaders() {
        XCTAssertNil(SettingsTabGroup.main.title)
        XCTAssertEqual(SettingsTabGroup.developer.title, "Developer")
        XCTAssertEqual(SettingsTabGroup.notch.title, "Notch")
        XCTAssertNil(SettingsTabGroup.app.title)
    }

    func testGroupsCoverEveryTabExactlyOnce() {
        let listed = SettingsTabGroup.allCases.flatMap(\.tabs)
        XCTAssertEqual(listed, SettingsTab.allCases)
        XCTAssertEqual(Set(listed).count, listed.count)
    }

    func testTitlesAreUniqueAndSentenceCase() {
        let titles = SettingsTab.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertTrue(titles.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(SettingsTab.claudeCode.title, "Claude Code")
        XCTAssertEqual(SettingsTab.huds.title, "HUDs")
    }

    func testSymbolsAreUniqueAndExist() {
        let symbols = SettingsTab.allCases.map(\.symbol)
        XCTAssertEqual(Set(symbols).count, symbols.count)
        for symbol in symbols {
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), symbol)
        }
    }

    func testIdentifiersAreUnique() {
        let ids = SettingsTab.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testInitFromTitleRoundTrips() {
        for tab in SettingsTab.allCases {
            XCTAssertEqual(SettingsTab(title: tab.title), tab)
        }
        XCTAssertNil(SettingsTab(title: "Nope"))
        XCTAssertNil(SettingsTab(title: "general"))
    }

    @MainActor
    func testOpenByTabRequestsItAndPresentsTheWindow() {
        var presented = 0
        let navigation = SettingsNavigation(present: { presented += 1 })
        XCTAssertNil(navigation.requested)
        navigation.open(.claudeCode)
        XCTAssertEqual(navigation.requested, .claudeCode)
        XCTAssertEqual(presented, 1)
        navigation.open(.about)
        XCTAssertEqual(navigation.requested, .about)
        XCTAssertEqual(presented, 2)
    }

    @MainActor
    func testOpenByTitleMapsToTheTabAndFallsBackToGeneral() {
        let navigation = SettingsNavigation(present: {})
        navigation.open("GitHub")
        XCTAssertEqual(navigation.requested, .github)
        navigation.open("About")
        XCTAssertEqual(navigation.requested, .about)
        navigation.open("Missing")
        XCTAssertEqual(navigation.requested, .general)
    }

    func testFeatureOffHintsNameExistingTabs() {
        for view in NotchViews.allCases {
            let tab = NotchTabCatalog.settingsTab(for: view)
            let hint = NotchTabCatalog.featureOffHint(for: view)
            if view == .home {
                XCTAssertNil(tab)
                XCTAssertNil(hint)
                continue
            }
            let resolved = try? XCTUnwrap(tab, "\(view)")
            XCTAssertNotNil(resolved)
            XCTAssertTrue(SettingsTab.allCases.contains { $0 == resolved })
            XCTAssertEqual(hint, "Turned off in Settings → \(resolved?.title ?? "").")
        }
    }

    func testFeatureOffHintsPointAtTheTabThatOwnsTheSwitch() {
        XCTAssertEqual(NotchTabCatalog.featureOffHint(for: .agents), "Turned off in Settings → Claude Code.")
        XCTAssertEqual(NotchTabCatalog.featureOffHint(for: .dev), "Turned off in Settings → Dev.")
        XCTAssertEqual(NotchTabCatalog.featureOffHint(for: .shelf), "Turned off in Settings → Shelf.")
        XCTAssertEqual(NotchTabCatalog.featureOffHint(for: .vitrin), "Turned off in Settings → Vitrin.")
        XCTAssertEqual(NotchTabCatalog.featureOffHint(for: .notifications), "Turned off in Settings → Notifications.")
    }

    func testEveryNotchTabHasASettingsTabInTheNotchOrDeveloperGroup() {
        let allowed: Set<SettingsTabGroup> = [.notch, .developer]
        for view in NotchViews.allCases where view != .home {
            let tab = NotchTabCatalog.settingsTab(for: view)
            XCTAssertTrue(tab.map { allowed.contains($0.group) } ?? false, "\(view)")
        }
    }
}
