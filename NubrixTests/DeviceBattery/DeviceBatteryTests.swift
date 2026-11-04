import XCTest
@testable import Nubrix

final class DeviceBatteryTests: XCTestCase {
    private func device(_ id: String, left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil, single: Int? = nil) -> DeviceBattery {
        DeviceBattery(id: id, name: id, kind: .airpods, left: left, right: right, caseLevel: caseLevel, single: single)
    }

    func testKindFromName() {
        XCTAssertEqual(DeviceBatteryKind.detect(name: "Murat's AirPods Pro"), .airpodsPro)
        XCTAssertEqual(DeviceBatteryKind.detect(name: "AirPods"), .airpods)
        XCTAssertEqual(DeviceBatteryKind.detect(name: "AirPods Max"), .headphones)
        XCTAssertEqual(DeviceBatteryKind.detect(name: "Magic Mouse"), .mouse)
        XCTAssertEqual(DeviceBatteryKind.detect(name: "Magic Keyboard"), .keyboard)
        XCTAssertEqual(DeviceBatteryKind.detect(name: "Magic Trackpad"), .trackpad)
        XCTAssertEqual(DeviceBatteryKind.detect(name: "Beats Studio"), .headphones)
        XCTAssertEqual(DeviceBatteryKind.detect(name: "Thing"), .other)
    }

    func testKindFromClass() {
        XCTAssertEqual(DeviceBatteryKind.detect(name: "X", majorClass: 4, minorClass: 6), .headphones)
        XCTAssertEqual(DeviceBatteryKind.detect(name: "X", majorClass: 5, minorClass: 0x10), .keyboard)
        XCTAssertEqual(DeviceBatteryKind.detect(name: "X", majorClass: 5, minorClass: 0x20), .mouse)
        XCTAssertEqual(DeviceBatteryKind.detect(name: "X", majorClass: 5, minorClass: 0x25), .trackpad)
        XCTAssertEqual(DeviceBatteryKind.detect(name: "X", majorClass: 1), .other)
    }

    func testSymbolsExist() {
        let kinds: [DeviceBatteryKind] = [.airpodsPro, .airpods, .headphones, .mouse, .keyboard, .trackpad, .other]
        for kind in kinds {
            XCTAssertNotNil(NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil), kind.symbol)
        }
    }

    func testNormalizeAndMerge() {
        XCTAssertEqual(DeviceBattery.normalize(address: "AA-BB-cc-01-02-03"), "aabbcc010203")
        XCTAssertEqual(DeviceBattery.normalize(address: "aa:bb:cc:01:02:03"), "aabbcc010203")
        let bt = [device("aabbcc010203", left: 80, right: 75)]
        let hid = [device("aabbcc010203", single: 50), device("112233445566", single: 40)]
        let merged = DeviceBattery.merge(bluetooth: bt, hid: hid)
        XCTAssertEqual(merged.map(\.id), ["aabbcc010203", "112233445566"])
        XCTAssertNil(merged[0].single)
    }

    func testMergeFillsMissingLevel() {
        let merged = DeviceBattery.merge(bluetooth: [device("a1")], hid: [device("a1", single: 33)])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].single, 33)
    }

    func testLevelTreatsZeroAsUnknown() {
        XCTAssertNil(DeviceBattery.level(0))
        XCTAssertNil(DeviceBattery.level(nil))
        XCTAssertNil(DeviceBattery.level(255))
        XCTAssertEqual(DeviceBattery.level(64), 64)
    }

    func testLowestAndSummary() {
        let pods = device("a", left: 80, right: 75, caseLevel: 60)
        XCTAssertEqual(pods.lowest, 75)
        XCTAssertEqual(pods.summary, "L 80%  R 75%  Case 60%")
        XCTAssertEqual(device("b", single: 65).summary, "65%")
        XCTAssertEqual(device("c", caseLevel: 10).lowest, 10)
        XCTAssertNil(device("d").lowest)
        XCTAssertEqual(device("d").summary, "")
    }

    func testCanRunGate() {
        XCTAssertFalse(DeviceBatteryStore.canRun(enabled: true, firstLaunch: nil))
        XCTAssertFalse(DeviceBatteryStore.canRun(enabled: true, firstLaunch: true))
        XCTAssertFalse(DeviceBatteryStore.canRun(enabled: false, firstLaunch: false))
        XCTAssertTrue(DeviceBatteryStore.canRun(enabled: true, firstLaunch: false))
    }

    func testFirstPassDoesNotAnnounce() {
        var t = DeviceBatteryTracker()
        XCTAssertTrue(t.process([device("a", left: 90)], firstPass: true).isEmpty)
        XCTAssertTrue(t.process([device("a", left: 90)], firstPass: false).isEmpty)
    }

    func testAnnouncesNewDeviceOnceWhenLevelKnown() {
        var t = DeviceBatteryTracker()
        _ = t.process([], firstPass: true)
        XCTAssertTrue(t.process([device("a")], firstPass: false).isEmpty)
        XCTAssertEqual(t.process([device("a", left: 90)], firstPass: false).count, 1)
        XCTAssertTrue(t.process([device("a", left: 90)], firstPass: false).isEmpty)
    }

    func testConnectEventAnnouncesAgainAfterReconnect() {
        var t = DeviceBatteryTracker()
        _ = t.process([device("a", left: 90)], firstPass: true)
        t.connected("a")
        XCTAssertEqual(t.process([device("a", left: 90)], firstPass: false).count, 1)
    }

    func testLowBatteryAlertOncePerConnection() {
        var t = DeviceBatteryTracker()
        _ = t.process([device("a", left: 50)], firstPass: true)
        XCTAssertTrue(t.process([device("a", left: 25)], firstPass: false).isEmpty)
        XCTAssertEqual(t.process([device("a", left: 20)], firstPass: false).count, 1)
        XCTAssertTrue(t.process([device("a", left: 15)], firstPass: false).isEmpty)
        // gone, then back with a low level: one banner for the connection, not two
        _ = t.process([], firstPass: false)
        XCTAssertEqual(t.process([device("a", left: 15)], firstPass: false).count, 1)
        XCTAssertTrue(t.process([device("a", left: 14)], firstPass: false).isEmpty)
    }

    func testRingTints() {
        XCTAssertEqual(batteryRingTint(100), .green)
        XCTAssertEqual(batteryRingTint(21), .green)
        XCTAssertEqual(batteryRingTint(20), .orange)
        XCTAssertEqual(batteryRingTint(11), .orange)
        XCTAssertEqual(batteryRingTint(10), .red)
        XCTAssertEqual(batteryRingTint(0), .red)
    }
}
