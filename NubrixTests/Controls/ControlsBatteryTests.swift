import XCTest
@testable import Nubrix

final class ControlsBatteryTests: XCTestCase {
    func testSingleLevelHasNoLabel() {
        let battery = DeviceBattery(id: "a", name: "Mouse", kind: .other, single: 82)
        let parts = ControlsBattery.parts(battery)
        XCTAssertEqual(parts, [ControlsBatteryPart(label: nil, level: 82)])
        XCTAssertEqual(ControlsBattery.text(parts), "82%")
    }

    func testAirPodsPartsKeepOrderAndLabels() {
        let battery = DeviceBattery(id: "a", name: "AirPods", kind: .other, left: 80, right: 82, caseLevel: 40)
        XCTAssertEqual(ControlsBattery.text(ControlsBattery.parts(battery)), "L 80% · R 82% · Case 40%")
    }

    func testCaseOnlyAndEmpty() {
        let caseOnly = DeviceBattery(id: "a", name: "AirPods", kind: .other, caseLevel: 55)
        XCTAssertEqual(ControlsBattery.text(ControlsBattery.parts(caseOnly)), "Case 55%")
        XCTAssertTrue(ControlsBattery.parts(DeviceBattery(id: "a", name: "x", kind: .other)).isEmpty)
    }

    func testMatchByAddressInAudioUID() {
        let list = [
            ControlsBluetoothDevice(id: "aa-bb-cc-dd-ee-ff", name: "Pods", symbol: "x", connected: true),
            ControlsBluetoothDevice(id: "11-22-33-44-55-66", name: "Other", symbol: "x", connected: true),
        ]
        XCTAssertEqual(ControlsBattery.match(uid: "AA-BB-CC-DD-EE-FF:output", name: "Whatever", in: list)?.name, "Pods")
    }

    func testMatchFallsBackToName() {
        let list = [ControlsBluetoothDevice(id: "aa-bb-cc-dd-ee-ff", name: "Alex's AirPods Pro", symbol: "x", connected: true)]
        XCTAssertEqual(ControlsBattery.match(uid: "BuiltInSpeakerDevice", name: "alex's airpods pro ", in: list)?.id, "aa-bb-cc-dd-ee-ff")
        XCTAssertNil(ControlsBattery.match(uid: "BuiltInSpeakerDevice", name: "MacBook Speakers", in: list))
    }

    func testControlsTabIsTaller() {
        XCTAssertEqual(openNotchSize(for: .controls).height, 270)
        for view in NotchViews.allCases where view != .controls {
            XCTAssertEqual(openNotchSize(for: view), openNotchSize)
        }
        XCTAssertEqual(notchWindowHeight(forOpenNotchHeight: openNotchSize.height), windowSize.height)
        XCTAssertEqual(notchWindowHeight(forOpenNotchHeight: 270), maxWindowSize.height)
        XCTAssertGreaterThan(maxWindowSize.height, windowSize.height)
    }
}
