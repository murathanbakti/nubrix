import Foundation
import IOKit

// MARK: - Model (pure)

struct HIDUsage: Hashable {
    var page: Int
    var usage: Int
}

struct HIDDeviceInfo: Equatable {
    var product: String?
    var manufacturer: String?
    var transport: String?
    var builtIn: Bool
    var vendorID: Int
    var productID: Int
    var locationID: Int?
    var primaryUsage: HIDUsage?
    var usagePairs: [HIDUsage]

    /// The usage pairs, or the primary usage when the device lists none.
    var usages: [HIDUsage] {
        if !usagePairs.isEmpty { return usagePairs }
        return primaryUsage.map { [$0] } ?? []
    }
}

struct MouseDevice: Hashable, Identifiable {
    var id: String
    var name: String
    var transport: String?
    var vendorID: Int = 0
    var productID: Int = 0

    /// Stable across USB ports and reconnects, unlike `id`.
    var key: String { "\(vendorID):\(productID):\(name)" }
}

enum MouseDeviceClassifier {
    private static let mouseUsage = HIDUsage(page: 1, usage: 2)
    private static let excludedTransports: Set<String> = ["fifo", "spi", "virtual", "audio"]
    private static let excludedNames = ["trackpad", "magic mouse", "virtual", "karabiner"]

    static func isWheelMouse(_ device: HIDDeviceInfo) -> Bool {
        guard device.usages.contains(mouseUsage), !device.builtIn else { return false }
        if let transport = device.transport?.lowercased(), excludedTransports.contains(transport) { return false }
        let product = device.product?.lowercased() ?? ""
        return !excludedNames.contains { product.contains($0) }
    }

    static func mice(from devices: [HIDDeviceInfo]) -> [MouseDevice] {
        var seen = Set<String>()
        var found: [MouseDevice] = []
        for device in devices where isWheelMouse(device) {
            let mouse = makeMouse(device)
            if seen.insert(mouse.id).inserted { found.append(mouse) }
        }
        return found.enumerated()
            .sorted { lhs, rhs in
                let order = lhs.element.name.localizedStandardCompare(rhs.element.name)
                return order == .orderedSame ? lhs.offset < rhs.offset : order == .orderedAscending
            }
            .map(\.element)
    }

    static func counted(_ mice: [MouseDevice], ignoring ignored: Set<String>) -> [MouseDevice] {
        mice.filter { !ignored.contains($0.key) }
    }

    private static func makeMouse(_ device: HIDDeviceInfo) -> MouseDevice {
        let trimmed = device.product?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = trimmed.isEmpty ? "Mouse" : trimmed
        let id: String
        if device.vendorID == 0, device.productID == 0, (device.locationID ?? 0) == 0 {
            id = name
        } else {
            id = "\(device.vendorID)-\(device.productID)-\(device.locationID ?? 0)"
        }
        return MouseDevice(id: id, name: name, transport: device.transport, vendorID: device.vendorID, productID: device.productID)
    }
}

// MARK: - I/O Registry

enum HIDRegistry {
    /// Reads every IOHIDDevice in the I/O Registry. Opens no device, so no permission is involved.
    static func devices() -> [HIDDeviceInfo] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var devices: [HIDDeviceInfo] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            devices.append(info(for: service))
            IOObjectRelease(service)
        }
        return devices
    }

    private static func info(for service: io_object_t) -> HIDDeviceInfo {
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        func int(_ key: String) -> Int? { (property(key) as? NSNumber)?.intValue }

        let primaryUsage: HIDUsage?
        if let page = int("PrimaryUsagePage"), let usage = int("PrimaryUsage") {
            primaryUsage = HIDUsage(page: page, usage: usage)
        } else {
            primaryUsage = nil
        }
        let pairs = (property("DeviceUsagePairs") as? [[String: Any]] ?? []).compactMap { pair -> HIDUsage? in
            guard let page = (pair["DeviceUsagePage"] as? NSNumber)?.intValue,
                  let usage = (pair["DeviceUsage"] as? NSNumber)?.intValue else { return nil }
            return HIDUsage(page: page, usage: usage)
        }
        return HIDDeviceInfo(
            product: property("Product") as? String,
            manufacturer: property("Manufacturer") as? String,
            transport: property("Transport") as? String,
            builtIn: (property("Built-In") as? NSNumber)?.boolValue ?? false,
            vendorID: int("VendorID") ?? 0,
            productID: int("ProductID") ?? 0,
            locationID: int("LocationID"),
            primaryUsage: primaryUsage,
            usagePairs: pairs
        )
    }
}

// MARK: - Monitoring

protocol MouseDeviceMonitoring: AnyObject {
    var onChange: (([MouseDevice]) -> Void)? { get set }
    var isRunning: Bool { get }
    func start()
    func stop()
    /// One-shot read, no notifications.
    func scan() -> [MouseDevice]
}

final class HIDMouseMonitor: MouseDeviceMonitoring {
    var onChange: (([MouseDevice]) -> Void)?
    private(set) var isRunning = false

    private var port: IONotificationPortRef?
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    private var rescan: DispatchWorkItem?
    private var last: [MouseDevice]?

    func scan() -> [MouseDevice] {
        MouseDeviceClassifier.mice(from: HIDRegistry.devices())
    }

    func start() {
        guard !isRunning else { return }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        isRunning = true
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)

        let callback: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let monitor = Unmanaged<HIDMouseMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.drain(iterator)
            monitor.scheduleRescan()
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("IOHIDDevice"), callback, refcon, &matchedIterator)
        IOServiceAddMatchingNotification(port, kIOTerminatedNotification, IOServiceMatching("IOHIDDevice"), callback, refcon, &terminatedIterator)
        drain(matchedIterator)
        drain(terminatedIterator)

        let mice = scan()
        last = mice
        onChange?(mice)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        rescan?.cancel()
        rescan = nil
        if matchedIterator != 0 { IOObjectRelease(matchedIterator) }
        if terminatedIterator != 0 { IOObjectRelease(terminatedIterator) }
        matchedIterator = 0
        terminatedIterator = 0
        if let port { IONotificationPortDestroy(port) }
        port = nil
        last = nil
    }

    private func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
        }
    }

    /// A terminated service can still be listed for a moment, and a Bluetooth connect fires several notifications.
    private func scheduleRescan() {
        rescan?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, isRunning else { return }
            let mice = scan()
            guard mice != last else { return }
            last = mice
            onChange?(mice)
        }
        rescan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    deinit { stop() }
}
