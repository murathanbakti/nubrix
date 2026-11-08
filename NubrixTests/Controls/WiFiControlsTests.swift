import XCTest
@testable import Nubrix

final class WiFiControlsTests: XCTestCase {
    func testBarsFromRSSI() {
        XCTAssertEqual(WiFiMetrics.bars(rssi: -30), 4)
        XCTAssertEqual(WiFiMetrics.bars(rssi: -54), 4)
        XCTAssertEqual(WiFiMetrics.bars(rssi: -55), 3)
        XCTAssertEqual(WiFiMetrics.bars(rssi: -66), 3)
        XCTAssertEqual(WiFiMetrics.bars(rssi: -67), 2)
        XCTAssertEqual(WiFiMetrics.bars(rssi: -74), 2)
        XCTAssertEqual(WiFiMetrics.bars(rssi: -75), 1)
        XCTAssertEqual(WiFiMetrics.bars(rssi: -95), 1)
    }

    func testMergeDedupesSortsAndDropsCurrentAndHidden() {
        let raw: [(ssid: String?, rssi: Int, secured: Bool)] = [
            ("Office", -70, true),
            ("Office", -50, true),
            ("Cafe", -60, false),
            (nil, -40, true),
            ("", -41, true),
            ("Home", -30, true),
            ("Alpha", -60, true),
        ]
        let result = WiFiMetrics.merge(raw, current: "Home")
        XCTAssertEqual(result.map(\.ssid), ["Office", "Alpha", "Cafe"])
        XCTAssertEqual(result.first?.rssi, -50)
        XCTAssertEqual(result.last?.secured, false)
    }

    func testMergeOfNothingIsEmpty() {
        XCTAssertTrue(WiFiMetrics.merge([], current: nil).isEmpty)
    }

    func testSecuredNetworksOpenSettingsOpenOnesJoin() {
        XCTAssertEqual(WiFiMetrics.joinAction(for: WiFiNetwork(ssid: "A", rssi: -50, secured: true)), .openSettings)
        XCTAssertEqual(WiFiMetrics.joinAction(for: WiFiNetwork(ssid: "B", rssi: -50, secured: false)), .join)
        XCTAssertEqual(WiFiMetrics.securityText(WiFiNetwork(ssid: "A", rssi: 0, secured: true)), "Secured")
        XCTAssertEqual(WiFiMetrics.securityText(WiFiNetwork(ssid: "B", rssi: 0, secured: false)), "Open")
    }

    func testScansAreTwentySecondsApart() {
        let now = Date()
        XCTAssertTrue(WiFiMetrics.shouldScan(now: now, lastScan: nil))
        XCTAssertFalse(WiFiMetrics.shouldScan(now: now, lastScan: now.addingTimeInterval(-19)))
        XCTAssertTrue(WiFiMetrics.shouldScan(now: now, lastScan: now.addingTimeInterval(-20)))
        XCTAssertTrue(WiFiMetrics.shouldScan(now: now, lastScan: now, force: true))
    }

    func testNetworkNamesAskOnlyWhenNotAskedYet() {
        XCTAssertEqual(WiFiMetrics.namesAction(.notDetermined), .ask)
        XCTAssertEqual(WiFiMetrics.namesAction(.denied), .openSettings)
        XCTAssertEqual(WiFiMetrics.namesAction(.granted), .none)
    }

    func testTabOrderAndSavedValuesStillWork() {
        XCTAssertEqual(ControlsListTab.allCases.map(\.rawValue), ["Wi-Fi", "Bluetooth", "Output", "Input", "Drives"])
        // Values saved before Wi-Fi existed.
        for old in ["Output", "Input", "Bluetooth", "Drives"] {
            XCTAssertEqual(ControlsListTab.resolve(old).rawValue, old)
        }
        XCTAssertEqual(ControlsListTab.resolve(""), .wifi)
        XCTAssertEqual(ControlsListTab.resolve("nonsense"), .wifi)
    }
}
