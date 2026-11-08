import CoreWLAN
import Foundation

// MARK: - Tabs

/// The list tabs on the right of the Controls tab. Raw values are what `@AppStorage` saved, so
/// existing saved values keep working.
enum ControlsListTab: String, CaseIterable {
    case wifi = "Wi-Fi"
    case bluetooth = "Bluetooth"
    case output = "Output"
    case input = "Input"
    case drives = "Drives"

    /// Wi-Fi is the first tab. An empty or unknown saved value falls back to it.
    static func resolve(_ raw: String) -> ControlsListTab {
        ControlsListTab(rawValue: raw) ?? .wifi
    }
}

// MARK: - Model

struct WiFiNetwork: Identifiable, Equatable, Sendable {
    var ssid: String
    var rssi: Int
    var secured: Bool
    var id: String { ssid }
}

/// What the Wi-Fi interface looked like on the last read.
struct WiFiState: Equatable, Sendable {
    /// False when this Mac has no Wi-Fi interface.
    var available = true
    var powered = true
    /// Joined to a network (the name may still be hidden without Location access).
    var connected = false
    var ssid: String?
    var rssi = 0
    var ip: String?
    var networks: [WiFiNetwork] = []
}

// MARK: - Pure rules

enum WiFiMetrics {
    /// Signal bars (1 to 4) from RSSI in dBm: above -55 is 4, above -67 is 3, above -75 is 2, else 1.
    static func bars(rssi: Int) -> Int {
        if rssi > -55 { return 4 }
        if rssi > -67 { return 3 }
        if rssi > -75 { return 2 }
        return 1
    }

    /// Scan results as shown in the list: no hidden (empty) names, the current network left out,
    /// one entry per name (the strongest), strongest first, then by name.
    static func merge(
        _ raw: [(ssid: String?, rssi: Int, secured: Bool)],
        current: String?
    ) -> [WiFiNetwork] {
        var best: [String: WiFiNetwork] = [:]
        for item in raw {
            guard let ssid = item.ssid, !ssid.isEmpty, ssid != current else { continue }
            let candidate = WiFiNetwork(ssid: ssid, rssi: item.rssi, secured: item.secured)
            if let existing = best[ssid], existing.rssi >= candidate.rssi { continue }
            best[ssid] = candidate
        }
        return best.values.sorted {
            if $0.rssi != $1.rssi { return $0.rssi > $1.rssi }
            return $0.ssid.localizedCaseInsensitiveCompare($1.ssid) == .orderedAscending
        }
    }

    static func securityText(_ network: WiFiNetwork) -> String { network.secured ? "Secured" : "Open" }

    /// Scans are at most this far apart.
    static let scanInterval: TimeInterval = 20

    static func shouldScan(now: Date, lastScan: Date?, force: Bool = false) -> Bool {
        guard let lastScan else { return true }
        return force || now.timeIntervalSince(lastScan) >= scanInterval
    }

    /// What tapping a Wi-Fi row does: open networks join in place; secured ones go to Wi-Fi settings
    /// (Nubrix never asks for or handles a password).
    enum JoinAction: Equatable { case join, openSettings }

    static func joinAction(for network: WiFiNetwork) -> JoinAction { network.secured ? .openSettings : .join }

    /// What "Show network names" does for a Location status.
    enum NamesAction: Equatable { case ask, openSettings, none }

    static func namesAction(_ status: PermissionStatus) -> NamesAction {
        switch status {
        case .notDetermined: return .ask
        case .denied: return .openSettings
        case .granted, .unavailable: return .none
        }
    }

    static let settingsURL = "x-apple.systempreferences:com.apple.wifi-settings-extension"
}

// MARK: - CoreWLAN

/// Reads and drives the Wi-Fi interface. Every call runs on the store's Wi-Fi queue, one at a time.
final class WiFiReader: @unchecked Sendable {
    private let client = CWWiFiClient.shared()
    private var scanned: [String: CWNetwork] = [:]
    private var cachedNetworks: [WiFiNetwork] = []
    private var lastScan: Date?

    /// Reads the interface; scans for networks when `scan` is set and the last scan is old enough.
    func read(scan: Bool, forceScan: Bool = false) -> WiFiState {
        guard let interface = client.interface() else {
            return WiFiState(available: false, powered: false)
        }
        var state = WiFiState()
        state.powered = interface.powerOn()
        guard state.powered else {
            cachedNetworks = []
            lastScan = nil
            return state
        }
        let rssi = interface.rssiValue()
        state.ssid = interface.ssid()
        state.rssi = rssi
        state.ip = Self.ipv4(of: interface.interfaceName)
        state.connected = state.ssid != nil || rssi != 0 || state.ip != nil

        if scan, WiFiMetrics.shouldScan(now: Date(), lastScan: lastScan, force: forceScan) {
            lastScan = Date()
            if let found = try? interface.scanForNetworks(withName: nil) {
                scanned = [:]
                var raw: [(ssid: String?, rssi: Int, secured: Bool)] = []
                for network in found {
                    if let ssid = network.ssid, !ssid.isEmpty { scanned[ssid] = network }
                    raw.append((network.ssid, network.rssiValue, !network.supportsSecurity(.none)))
                }
                cachedNetworks = WiFiMetrics.merge(raw, current: state.ssid)
            }
        }
        state.networks = cachedNetworks.filter { $0.ssid != state.ssid }
        return state
    }

    func setPower(_ on: Bool) throws {
        guard let interface = client.interface() else { throw CocoaError(.featureUnsupported) }
        try interface.setPower(on)
    }

    /// Joins an open network. Throws when it fails or the name is no longer in the last scan.
    func join(ssid: String) throws {
        guard let interface = client.interface(), let network = scanned[ssid] else {
            throw CocoaError(.fileNoSuchFile)
        }
        try interface.associate(to: network, password: nil)
        lastScan = nil
    }

    private static func ipv4(of name: String?) -> String? {
        guard let name else { return nil }
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = pointer {
            defer { pointer = entry.pointee.ifa_next }
            guard String(cString: entry.pointee.ifa_name) == name,
                  let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  entry.pointee.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
            if result == 0 { return String(cString: buffer) }
        }
        return nil
    }
}
