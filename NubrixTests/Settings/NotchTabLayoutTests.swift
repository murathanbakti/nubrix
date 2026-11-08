import XCTest
@testable import Nubrix

final class NotchTabLayoutTests: XCTestCase {
    func testSavedOrderWithoutControlsPutsItLast() {
        let saved: [NotchViews] = [.home, .shelf, .vitrin, .agents, .dev, .notifications]
        let ordered = NotchTabLayout.computeOrdered(saved).map(\.view)
        XCTAssertEqual(ordered.last, .controls)
        XCTAssertEqual(Set(ordered), Set(NotchViews.allCases))
    }

    func testControlsIsVisibleByDefault() {
        let visible = NotchTabLayout.computeVisible(order: NotchViews.allCases, hidden: []).map(\.view)
        XCTAssertTrue(visible.contains(.controls))
        XCTAssertEqual(visible.prefix(2).map { $0 }, [.home, .controls])
    }

    func testControlsCanBeHidden() {
        let visible = NotchTabLayout.computeVisible(order: NotchViews.allCases, hidden: [.controls]).map(\.view)
        XCTAssertFalse(visible.contains(.controls))
    }

    func testControlsTabHasNoSettingsSwitch() {
        XCTAssertNil(NotchTabCatalog.settingsTab(for: .controls))
        XCTAssertTrue(NotchTabLayout.isFeatureEnabled(.controls))
    }
}
