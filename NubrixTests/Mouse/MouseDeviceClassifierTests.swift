import XCTest
@testable import Nubrix

final class MouseDeviceClassifierTests: XCTestCase {
    private let mouse = HIDUsage(page: 1, usage: 2)

    private func device(
        _ product: String?, transport: String? = "USB", builtIn: Bool = false,
        vendor: Int = 1, productID: Int = 1, location: Int? = 100,
        primary: HIDUsage? = nil, pairs: [HIDUsage]? = nil
    ) -> HIDDeviceInfo {
        HIDDeviceInfo(
            product: product, manufacturer: nil, transport: transport, builtIn: builtIn,
            vendorID: vendor, productID: productID, locationID: location,
            primaryUsage: primary, usagePairs: pairs ?? [mouse]
        )
    }

    func testBuiltInTrackpadIsExcluded() {
        let trackpad = device(
            "Apple Internal Keyboard / Trackpad", transport: "FIFO", builtIn: true,
            pairs: [HIDUsage(page: 1, usage: 2), HIDUsage(page: 1, usage: 1), HIDUsage(page: 13, usage: 5)]
        )
        XCTAssertFalse(MouseDeviceClassifier.isWheelMouse(trackpad))
    }

    func testUSBAndBluetoothMiceAreIncluded() {
        XCTAssertTrue(MouseDeviceClassifier.isWheelMouse(device("USB Optical Mouse")))
        XCTAssertTrue(MouseDeviceClassifier.isWheelMouse(device("MX Master 3S", transport: "Bluetooth Low Energy")))
    }

    func testMagicMouseAndTrackpadAreExcluded() {
        XCTAssertFalse(MouseDeviceClassifier.isWheelMouse(device("Magic Mouse", transport: "Bluetooth")))
        XCTAssertFalse(MouseDeviceClassifier.isWheelMouse(device("Magic Trackpad", transport: "Bluetooth")))
    }

    func testNonMouseDevicesAreExcluded() {
        XCTAssertFalse(MouseDeviceClassifier.isWheelMouse(device("Keyboard", pairs: [HIDUsage(page: 1, usage: 6)])))
        XCTAssertFalse(MouseDeviceClassifier.isWheelMouse(device("Headset", transport: "Audio", pairs: [HIDUsage(page: 12, usage: 1)])))
    }

    func testVirtualDevicesAreExcluded() {
        XCTAssertFalse(MouseDeviceClassifier.isWheelMouse(device("Karabiner DriverKit VirtualHIDPointing")))
        XCTAssertFalse(MouseDeviceClassifier.isWheelMouse(device("Some Mouse", transport: "Virtual")))
    }

    func testPrimaryUsageIsUsedWhenPairsAreEmpty() {
        XCTAssertTrue(MouseDeviceClassifier.isWheelMouse(device("Plain Mouse", primary: mouse, pairs: [])))
        XCTAssertFalse(MouseDeviceClassifier.isWheelMouse(device("Nothing", primary: nil, pairs: [])))
    }

    func testDuplicateRegistryEntriesCollapse() {
        let mice = MouseDeviceClassifier.mice(from: [device("Mouse A"), device("Mouse A")])
        XCTAssertEqual(mice.count, 1)
    }

    func testSameModelAtTwoLocationsGivesTwoAndSummaryCounts() {
        let mice = MouseDeviceClassifier.mice(from: [device("Mouse A", location: 1), device("Mouse A", location: 2)])
        XCTAssertEqual(mice.count, 2)
    }

    func testMissingOrBlankProductIsCalledMouse() {
        XCTAssertEqual(MouseDeviceClassifier.mice(from: [device(nil)]).first?.name, "Mouse")
        XCTAssertEqual(MouseDeviceClassifier.mice(from: [device("   ")]).first?.name, "Mouse")
        XCTAssertEqual(MouseDeviceClassifier.mice(from: [device("  Padded  ")]).first?.name, "Padded")
    }

    func testIdFallsBackToNameWhenIdentifiersAreZero() {
        let mice = MouseDeviceClassifier.mice(from: [
            device("Mouse A", vendor: 0, productID: 0, location: nil),
            device("Mouse B", vendor: 0, productID: 0, location: nil)
        ])
        XCTAssertEqual(mice.count, 2)
    }

    func testMiceAreSortedByName() {
        let mice = MouseDeviceClassifier.mice(from: [
            device("Zed", productID: 1), device("alpha", productID: 2), device("Mouse 10", productID: 3), device("Mouse 2", productID: 4)
        ])
        XCTAssertEqual(mice.map(\.name), ["alpha", "Mouse 2", "Mouse 10", "Zed"])
    }

    func testCountedIgnoresByKey() {
        let mice = MouseDeviceClassifier.mice(from: [
            device("Keyboard", productID: 1), device("Mouse", productID: 2)
        ])
        let keyboard = mice.first { $0.name == "Keyboard" }!
        XCTAssertEqual(MouseDeviceClassifier.counted(mice, ignoring: []).count, 2)
        XCTAssertEqual(MouseDeviceClassifier.counted(mice, ignoring: [keyboard.key]).map(\.name), ["Mouse"])
    }

    func testOneKeyIgnoresTheSameModelAtEveryPort() {
        let mice = MouseDeviceClassifier.mice(from: [device("Mouse A", location: 1), device("Mouse A", location: 2)])
        XCTAssertEqual(mice.count, 2)
        XCTAssertEqual(Set(mice.map(\.key)).count, 1)
        XCTAssertTrue(MouseDeviceClassifier.counted(mice, ignoring: [mice[0].key]).isEmpty)
    }

    func testKeyFallsBackOnNameWhenIdentifiersAreZero() {
        let mice = MouseDeviceClassifier.mice(from: [device("Mouse A", vendor: 0, productID: 0, location: nil)])
        XCTAssertEqual(mice.first?.key, "0:0:Mouse A")
    }
}
