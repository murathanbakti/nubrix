import Foundation

/// What kind of device it is, used to pick an icon.
enum DeviceBatteryKind: Equatable {
    case airpodsPro, airpods, headphones, mouse, keyboard, trackpad, other

    var symbol: String {
        switch self {
        case .airpodsPro: "airpodspro"
        case .airpods: "airpods"
        case .headphones: "headphones"
        case .mouse: "magicmouse"
        case .keyboard: "keyboard"
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .other: "battery.100"
        }
    }

    /// Looks at the name first, then at the Bluetooth class (major 4 is audio, major 5 is a
    /// keyboard or pointing device).
    static func detect(name: String, majorClass: Int = 0, minorClass: Int = 0) -> DeviceBatteryKind {
        let n = name.lowercased()
        if n.contains("airpods max") { return .headphones }
        if n.contains("airpods pro") { return .airpodsPro }
        if n.contains("airpods") { return .airpods }
        if n.contains("trackpad") { return .trackpad }
        if n.contains("mouse") { return .mouse }
        if n.contains("keyboard") { return .keyboard }
        if n.contains("beats") || n.contains("headphone") || n.contains("headset") { return .headphones }
        switch majorClass {
        case 4: return .headphones
        case 5:
            switch minorClass & 0x30 {
            case 0x10, 0x30: return .keyboard
            case 0x20: return (minorClass & 0x0F) == 5 ? .trackpad : .mouse
            default: return .other
            }
        default: return .other
        }
    }
}

struct DeviceBattery: Identifiable, Equatable {
    /// Normalized address.
    let id: String
    var name: String
    var kind: DeviceBatteryKind
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var single: Int?

    /// Lowest level of the parts that are in use. The case only counts when nothing else is known.
    var lowest: Int? {
        let main = [left, right, single].compactMap { $0 }
        if let low = main.min() { return low }
        return caseLevel
    }

    var hasBattery: Bool { lowest != nil }

    /// Short text such as "L 80%  R 75%  Case 60%" or "65%".
    var summary: String {
        var parts: [String] = []
        if let left { parts.append("L \(left)%") }
        if let right { parts.append("R \(right)%") }
        if let caseLevel { parts.append("Case \(caseLevel)%") }
        if parts.isEmpty, let single { return "\(single)%" }
        if let single, !parts.isEmpty { parts.insert("\(single)%", at: 0) }
        return parts.joined(separator: "  ")
    }

    /// The parts to draw as rings, in order.
    var parts: [(label: String, level: Int)] {
        var out: [(String, Int)] = []
        if let left { out.append(("Left", left)) }
        if let right { out.append(("Right", right)) }
        if let caseLevel { out.append(("Case", caseLevel)) }
        if out.isEmpty, let single { out.append((name, single)) }
        return out
    }

    /// Lowercase hex only, so "AA-BB:cc" and "aabbcc" match.
    static func normalize(address: String) -> String {
        String(address.lowercased().filter { $0.isHexDigit })
    }

    /// Bluetooth list first, then HID devices that are not already in it. A HID entry fills in
    /// missing levels on a matching Bluetooth device.
    static func merge(bluetooth: [DeviceBattery], hid: [DeviceBattery]) -> [DeviceBattery] {
        var result = bluetooth
        for extra in hid {
            if let i = result.firstIndex(where: { $0.id == extra.id }) {
                if result[i].single == nil, result[i].left == nil, result[i].right == nil {
                    result[i].single = extra.single
                }
            } else {
                result.append(extra)
            }
        }
        return result
    }

    static func level(_ raw: Int?) -> Int? {
        guard let raw, raw > 0, raw <= 100 else { return nil }
        return raw
    }
}

/// Decides when to show a banner. No Bluetooth in here, so it can be tested.
struct DeviceBatteryTracker {
    static let lowLevel = 20

    private var known: Set<String> = []
    private var awaiting: Set<String> = []
    private var lowAlerted: Set<String> = []

    /// A connect event arrived. Wait for its level, then announce it.
    mutating func connected(_ id: String) {
        awaiting.insert(id)
        lowAlerted.remove(id)
    }

    mutating func disconnected(_ id: String) {
        known.remove(id)
        awaiting.remove(id)
        lowAlerted.remove(id)
    }

    /// Feed the connected devices. Returns the devices that need a banner now.
    /// `firstPass` seeds the list without announcing what was already connected.
    mutating func process(_ devices: [DeviceBattery], firstPass: Bool) -> [DeviceBattery] {
        let ids = Set(devices.map(\.id))
        for gone in known.subtracting(ids) { disconnected(gone) }
        for id in ids.subtracting(known) {
            known.insert(id)
            if !firstPass { awaiting.insert(id) }
        }
        var out: [DeviceBattery] = []
        for device in devices {
            guard let low = device.lowest else { continue }
            if awaiting.contains(device.id) {
                awaiting.remove(device.id)
                if low <= Self.lowLevel { lowAlerted.insert(device.id) }
                out.append(device)
            } else if low <= Self.lowLevel, !lowAlerted.contains(device.id) {
                lowAlerted.insert(device.id)
                out.append(device)
            }
        }
        return out
    }
}
