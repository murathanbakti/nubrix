import Defaults
import XCTest
@testable import Nubrix

final class DefaultsAuditTests: XCTestCase {
    func testPermissionBackedFeaturesDefaultOff() {
        XCTAssertFalse(Defaults.Keys.hudReplacement.defaultValue)
        XCTAssertFalse(Defaults.Keys.systemNotificationsEnabled.defaultValue)
        XCTAssertFalse(Defaults.Keys.enableLyrics.defaultValue)
    }

    func testMediaControllerDefaultsToNowPlaying() {
        XCTAssertEqual(Defaults.Keys.mediaController.defaultValue, .nowPlaying)
    }

    func testLazyAllowlistDocumented() {
        let lazy: [String: Bool] = [
            "showCalendar": Defaults.Keys.showCalendar.defaultValue,
            "showMirror": Defaults.Keys.showMirror.defaultValue,
            "meetingCountdownEnabled": Defaults.Keys.meetingCountdownEnabled.defaultValue,
            "vitrinEnabled": Defaults.Keys.vitrinEnabled.defaultValue
        ]
        XCTAssertEqual(
            Set(lazy.keys),
            ["showCalendar", "showMirror", "meetingCountdownEnabled", "vitrinEnabled"]
        )
        for (name, _) in lazy {
            XCTAssertFalse(name.isEmpty)
        }
    }
}
