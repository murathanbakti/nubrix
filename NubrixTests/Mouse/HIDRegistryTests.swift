import XCTest
@testable import Nubrix

final class HIDRegistryTests: XCTestCase {
    func testReadingTheRegistryIsSafe() throws {
        let devices = HIDRegistry.devices()
        let mice = MouseDeviceClassifier.mice(from: devices)
        print("HIDRegistryTests: \(devices.count) HID devices, mice: \(mice.map(\.name))")
        for device in devices {
            print("HIDRegistryTests: \(device.product ?? "-") transport=\(device.transport ?? "-") builtIn=\(device.builtIn) usages=\(device.usages.map { "\($0.page)/\($0.usage)" })")
        }
        if devices.isEmpty { throw XCTSkip("No HID devices visible from the test host") }
        XCTAssertTrue(devices.contains { $0.product != nil })
    }

    func testMonitorStartAndStopAreIdempotent() {
        let monitor = HIDMouseMonitor()
        monitor.start()
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.stop()
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
    }
}
