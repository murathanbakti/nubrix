import Foundation
import SwiftUI

enum EverydayTint: Equatable {
    case white, green, orange, red, blue

    var color: Color {
        switch self {
        case .white: .white
        case .green: .green
        case .orange: .orange
        case .red: .red
        case .blue: .blue
        }
    }
}

/// One small alert shown in the notch for a few seconds.
struct EverydayAlert: Identifiable, Equatable {
    enum Action: Equatable {
        case eject(URL)
        case showInFinder(URL)

        var label: String {
            switch self {
            case .eject: "Eject"
            case .showInFinder: "Show"
            }
        }
    }

    let id: UUID
    var symbol: String
    var tint: EverydayTint
    var title: String
    var detail: String?
    /// Short text for the closed notch. Falls back to `title`.
    var headerTitle: String?
    /// Small grey text on the right of the closed notch.
    var meta: String?
    var action: Action?

    init(id: UUID = UUID(), symbol: String, tint: EverydayTint, title: String, detail: String? = nil,
         headerTitle: String? = nil, meta: String? = nil, action: Action? = nil) {
        self.id = id
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.detail = detail
        self.headerTitle = headerTitle
        self.meta = meta
        self.action = action
    }
}

// MARK: - Sound output

struct SoundDevice: Equatable {
    var uid: String
    var name: String
    /// CoreAudio transport type (four character code).
    var transport: UInt32

    static func code(_ s: String) -> UInt32 {
        s.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    static let builtIn = code("bltn")
    static let bluetooth = code("blue")
    static let bluetoothLE = code("blea")
    static let hdmi = code("hdmi")
    static let displayPort = code("dprt")
    static let usb = code("usb ")
    static let airPlay = code("airp")

    var symbol: String {
        let n = name.lowercased()
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods max") { return "headphones" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("headphone") || n.contains("headset") || n.contains("beats") { return "headphones" }
        switch transport {
        case Self.builtIn: return "macbook"
        case Self.bluetooth, Self.bluetoothLE: return "headphones"
        case Self.hdmi, Self.displayPort: return "display"
        default: return "hifispeaker"
        }
    }

    var transportLabel: String? {
        switch transport {
        case Self.builtIn: "Built-in"
        case Self.bluetooth, Self.bluetoothLE: "Bluetooth"
        case Self.hdmi, Self.displayPort: "Display"
        case Self.usb: "USB"
        case Self.airPlay: "AirPlay"
        default: nil
        }
    }

    var alert: EverydayAlert {
        EverydayAlert(symbol: symbol, tint: .blue, title: "Sound plays on \(name)", headerTitle: "Sound output", meta: transportLabel)
    }
}

/// Decides when a change of the sound output is worth an alert: not the first
/// read, and only once the output has stayed put for a second.
struct SoundOutputTracker {
    static let debounce: TimeInterval = 1

    private var announced: String?
    private var seeded = false
    private var pending: (device: SoundDevice, at: Date)?

    /// Call with every read of the default output device.
    mutating func observe(_ device: SoundDevice?, at: Date) {
        guard seeded else {
            seeded = true
            announced = device?.uid
            return
        }
        guard let device else { return }
        if device.uid == announced {
            pending = nil
        } else {
            pending = (device, at)
        }
    }

    /// Returns the device to announce once it has been stable long enough.
    mutating func settle(at: Date) -> SoundDevice? {
        guard let pending, at.timeIntervalSince(pending.at) >= Self.debounce else { return nil }
        self.pending = nil
        announced = pending.device.uid
        return pending.device
    }
}

// MARK: - Drives

struct DriveVolume: Equatable {
    var path: String
    var name: String
    var isInternal: Bool
    var isRemovable: Bool
    var isEjectable: Bool
    var isLocal: Bool
    var isBrowsable: Bool
    var isDiskImage: Bool
    var total: Int64?
    var free: Int64?

    var url: URL { URL(fileURLWithPath: path) }

    /// Only drives and cards someone plugged in: not the Mac's own disk,
    /// network shares, hidden system volumes or disk images.
    var isUserVisible: Bool {
        guard isLocal, isBrowsable, !isDiskImage else { return false }
        guard path != "/", !path.hasPrefix("/System/"), !path.hasPrefix("/private/") else { return false }
        return !isInternal || isRemovable || isEjectable
    }

    static func isDiskImage(protocolName: String?, model: String?) -> Bool {
        if protocolName == "Virtual Interface" { return true }
        return model?.contains("Disk Image") ?? false
    }

    static func freeText(free: Int64?, total: Int64?) -> String? {
        guard let free, let total, total > 0 else { return nil }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return "\(f.string(fromByteCount: free)) free of \(f.string(fromByteCount: total))"
    }

    var connectedAlert: EverydayAlert {
        EverydayAlert(symbol: "externaldrive.fill", tint: .green, title: "\(name) connected",
                      detail: Self.freeText(free: free, total: total), headerTitle: "Drive", meta: name,
                      action: .eject(url))
    }
}

enum DriveAlerts {
    static func unplug(name: String) -> EverydayAlert {
        EverydayAlert(symbol: "checkmark.circle.fill", tint: .green, title: "\(name) can be unplugged",
                      headerTitle: "Drive", meta: name)
    }

    static func ejectFailed(name: String, url: URL) -> EverydayAlert {
        EverydayAlert(symbol: "exclamationmark.triangle.fill", tint: .orange, title: "Couldn't eject \(name)",
                      detail: "Eject it in Finder", headerTitle: "Drive", meta: name, action: .showInFinder(url))
    }
}

/// Remembers the drives that were announced so the unplug alert only appears for them.
struct DriveTracker {
    private var known: [String: String] = [:]

    mutating func seed(_ volumes: [DriveVolume]) {
        for v in volumes where v.isUserVisible { known[v.path] = v.name }
    }

    mutating func mounted(_ volume: DriveVolume) -> EverydayAlert? {
        guard volume.isUserVisible else { return nil }
        known[volume.path] = volume.name
        return volume.connectedAlert
    }

    /// Called before the volume goes away, while its details can still be read.
    mutating func willUnmount(_ volume: DriveVolume) {
        if volume.isUserVisible { known[volume.path] = volume.name }
    }

    mutating func unmounted(path: String) -> EverydayAlert? {
        guard let name = known.removeValue(forKey: path) else { return nil }
        return DriveAlerts.unplug(name: name)
    }
}

// MARK: - Microphone and camera

struct MicCameraResult: Equatable {
    var mic: Bool
    var camera: Bool

    var alert: EverydayAlert {
        let title: String
        let header: String
        switch (mic, camera) {
        case (true, true): title = "Camera and microphone on"; header = "Camera and mic"
        case (false, true): title = "Camera on"; header = "Camera"
        default: title = "Microphone on"; header = "Microphone"
        }
        let symbol = camera ? "video.fill" : "mic.fill"
        return EverydayAlert(symbol: symbol, tint: camera ? .green : .orange, title: title, headerTitle: header)
    }
}

/// Alerts when the microphone or camera starts, but only if it was off for at
/// least 5 seconds, so apps that open and close them quickly do not repeat it.
struct MicCameraTracker {
    static let rearm: TimeInterval = 5

    private var seeded = false
    private var micOn = false
    private var cameraOn = false
    private var micOffAt: Date?
    private var cameraOffAt: Date?
    /// True while the camera is running because of Nubrix's own Mirror.
    private var ownCamera = false

    /// `cameraIsOurs` is true while Nubrix's Mirror is open. The first call
    /// only records the state.
    mutating func update(mic: Bool, camera rawCamera: Bool, cameraIsOurs: Bool, at: Date) -> MicCameraResult? {
        if cameraIsOurs && rawCamera { ownCamera = true }
        if !rawCamera { ownCamera = false }
        let camera = rawCamera && !ownCamera

        defer {
            seeded = true
            if micOn && !mic { micOffAt = at }
            if cameraOn && !camera { cameraOffAt = at }
            micOn = mic
            cameraOn = camera
        }
        guard seeded else { return nil }

        let micStarted = mic && !micOn && Self.armed(micOffAt, at)
        let cameraStarted = camera && !cameraOn && Self.armed(cameraOffAt, at)
        guard micStarted || cameraStarted else { return nil }
        return MicCameraResult(mic: mic, camera: camera)
    }

    private static func armed(_ offAt: Date?, _ now: Date) -> Bool {
        guard let offAt else { return true }
        return now.timeIntervalSince(offAt) >= rearm
    }

    /// "Zoom", not "zoom.us Helper".
    static func cleanAppName(_ name: String) -> String {
        var result = name
        if let range = result.range(of: " Helper") { result = String(result[..<range.lowerBound]) }
        return result.trimmingCharacters(in: .whitespaces)
    }

    static func detail(app: String?) -> String? {
        guard let app, !app.isEmpty else { return nil }
        return "Used by \(app)"
    }
}

// MARK: - Internet

enum InternetEvent: Equatable {
    case offline, backOnline

    var alert: EverydayAlert {
        switch self {
        case .offline:
            EverydayAlert(symbol: "wifi.slash", tint: .red, title: "You're offline", detail: "Check your Wi-Fi or cable", headerTitle: "Internet")
        case .backOnline:
            EverydayAlert(symbol: "wifi", tint: .green, title: "Back online", headerTitle: "Internet")
        }
    }
}

/// Alerts when the connection stays gone for 3 seconds, and when it returns
/// after such an alert. Never on launch.
struct InternetTracker {
    static let offlineDelay: TimeInterval = 3

    private var online: Bool?
    private var offlineSince: Date?
    private var alertedOffline = false

    mutating func update(satisfied: Bool, at: Date) -> InternetEvent? {
        defer { online = satisfied }
        guard let was = online else { return nil }
        if satisfied {
            offlineSince = nil
            if alertedOffline {
                alertedOffline = false
                return .backOnline
            }
        } else if was {
            offlineSince = at
        }
        return nil
    }

    /// Call 3 seconds after the connection went away.
    mutating func settle(at: Date) -> InternetEvent? {
        guard online == false, !alertedOffline, let since = offlineSince,
              at.timeIntervalSince(since) >= Self.offlineDelay else { return nil }
        alertedOffline = true
        return .offline
    }
}
