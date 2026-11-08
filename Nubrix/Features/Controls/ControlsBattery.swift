import Foundation

/// One battery level of a device: "L 80%", "Case 40%" or a bare "82%" when there is no label.
struct ControlsBatteryPart: Equatable, Sendable {
    var label: String?
    var level: Int

    var text: String { label.map { "\($0) \(level)%" } ?? "\(level)%" }
}

/// Pure helpers for the battery text in the Controls tab.
enum ControlsBattery {
    /// Parts in display order: left, right, case. A device with one level gets a single unlabeled part.
    static func parts(_ battery: DeviceBattery) -> [ControlsBatteryPart] {
        var out: [ControlsBatteryPart] = []
        if let left = battery.left { out.append(ControlsBatteryPart(label: "L", level: left)) }
        if let right = battery.right { out.append(ControlsBatteryPart(label: "R", level: right)) }
        if let caseLevel = battery.caseLevel { out.append(ControlsBatteryPart(label: "Case", level: caseLevel)) }
        if out.isEmpty, let single = battery.single { out.append(ControlsBatteryPart(label: nil, level: single)) }
        return out
    }

    /// "82%" or "L 80% · R 82% · Case 40%".
    static func text(_ parts: [ControlsBatteryPart]) -> String {
        parts.map(\.text).joined(separator: " · ")
    }

    /// Finds the Bluetooth device behind an audio device. Core Audio UIDs of Bluetooth devices start
    /// with the address ("AA-BB-CC-DD-EE-FF:output"); the name is the fallback.
    static func match(uid: String, name: String, in devices: [ControlsBluetoothDevice]) -> ControlsBluetoothDevice? {
        let head = uid.split(separator: ":", maxSplits: 1).first.map(String.init) ?? uid
        let address = DeviceBattery.normalize(address: head)
        if address.count == 12, let found = devices.first(where: { DeviceBattery.normalize(address: $0.id) == address }) {
            return found
        }
        let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return nil }
        return devices.first { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == wanted }
    }
}

/// Pure layout rules for the capsule slider in the Controls tab.
enum ControlsSliderMetrics {
    static let height: CGFloat = 30
    /// The value text turns dark once the fill reaches within this distance of the right edge.
    static let valueClearance: CGFloat = 44

    /// Fill width: nothing at 0, at least the capsule height otherwise so the symbol sits inside.
    static func fillWidth(value: Double, width: CGFloat) -> CGFloat {
        let v = max(0, min(1, value))
        guard v > 0 else { return 0 }
        return min(width, max(height, width * v))
    }

    static func symbolOnFill(value: Double, width: CGFloat) -> Bool {
        fillWidth(value: value, width: width) >= 24
    }

    static func valueOnFill(value: Double, width: CGFloat) -> Bool {
        fillWidth(value: value, width: width) > width - valueClearance
    }

    /// Speaker symbol that follows the level, like macOS.
    static func speakerSymbol(level: Double, muted: Bool) -> String {
        if muted { return "speaker.slash.fill" }
        switch level {
        case ..<0.01: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    /// Battery numbers turn orange or red only when low (same rule as the ring).
    static func isLowBattery(_ level: Int) -> Bool { level <= DeviceBatteryTracker.lowLevel }
}
