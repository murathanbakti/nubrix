import Foundation
import IOBluetooth
import IOKit

/// Reads battery levels. Bluetooth first (AirPods, Beats), then the IOKit registry (Magic
/// Mouse, Keyboard, Trackpad). The Bluetooth battery properties are private, so every read
/// is checked first.
enum DeviceBatterySource {
    static func bluetoothDevices() -> [DeviceBattery] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        return paired.filter { $0.isConnected() }.compactMap(snapshot)
    }

    static func snapshot(_ device: IOBluetoothDevice) -> DeviceBattery? {
        guard let address = device.addressString else { return nil }
        let id = DeviceBattery.normalize(address: address)
        guard !id.isEmpty else { return nil }
        let name = device.name ?? device.nameOrAddress ?? "Bluetooth device"
        return DeviceBattery(
            id: id,
            name: name,
            kind: .detect(name: name, majorClass: Int(device.deviceClassMajor), minorClass: Int(device.deviceClassMinor)),
            left: percent(device, "batteryPercentLeft"),
            right: percent(device, "batteryPercentRight"),
            caseLevel: percent(device, "batteryPercentCase"),
            single: percent(device, "batteryPercentSingle")
        )
    }

    private static func percent(_ device: IOBluetoothDevice, _ key: String) -> Int? {
        guard device.responds(to: NSSelectorFromString(key)) else { return nil }
        return DeviceBattery.level((device.value(forKey: key) as? NSNumber)?.intValue)
    }

    static func hidDevices() -> [DeviceBattery] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var out: [DeviceBattery] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let level = DeviceBattery.level(property(entry, "BatteryPercent") as? Int) else { continue }
            let name = (property(entry, "Product") as? String) ?? "Device"
            let raw = (property(entry, "DeviceAddress") as? String) ?? (property(entry, "SerialNumber") as? String) ?? name
            let id = DeviceBattery.normalize(address: raw)
            out.append(DeviceBattery(id: id.isEmpty ? name.lowercased() : id, name: name, kind: .detect(name: name), single: level))
        }
        return out
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
