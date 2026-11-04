import Combine
import Defaults
import IOBluetooth
import SwiftUI

/// Receives Bluetooth connect and disconnect callbacks.
private final class DeviceBatteryListener: NSObject {
    var onConnect: ((IOBluetoothDevice) -> Void)?
    var onDisconnect: ((IOBluetoothDevice) -> Void)?

    @objc func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onConnect?(device)
    }

    @objc func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onDisconnect?(device)
    }
}

@MainActor
final class DeviceBatteryStore: ObservableObject {
    static let shared = DeviceBatteryStore()
    static let animation = Animation.spring(response: 0.38, dampingFraction: 0.82)

    @Published private(set) var devices: [DeviceBattery] = []
    @Published private(set) var banner: DeviceBattery?

    private var tracker = DeviceBatteryTracker()
    private var running = false
    private var seeded = false
    private var observing = false
    private var cancellable: AnyCancellable?
    private var timer: Timer?
    private var retryTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private let listener = DeviceBatteryListener()
    private var connectNote: IOBluetoothUserNotification?
    private var disconnectNotes: [String: IOBluetoothUserNotification] = [:]

    /// Only after the first launch is finished, so the Bluetooth prompt never appears during onboarding.
    nonisolated static func canRun(enabled: Bool, firstLaunch: Any?) -> Bool {
        guard enabled, let done = firstLaunch as? Bool else { return false }
        return !done
    }

    private var allowed: Bool {
        Self.canRun(enabled: Defaults[.deviceBatteryEnabled], firstLaunch: UserDefaults.standard.object(forKey: "firstLaunch"))
    }

    /// Safe to call more than once.
    func start() {
        if !observing {
            observing = true
            cancellable = Defaults.publisher(.deviceBatteryEnabled, options: [])
                .sink { [weak self] _ in Task { @MainActor in self?.start() } }
        }
        if allowed { begin() } else { end() }
    }

    func dismissBanner() {
        bannerTask?.cancel()
        withAnimation(Self.animation) { banner = nil }
    }

    private func begin() {
        guard !running else { return }
        running = true
        listener.onConnect = { [weak self] device in
            Task { @MainActor in self?.deviceConnected(device) }
        }
        listener.onDisconnect = { [weak self] device in
            Task { @MainActor in self?.deviceDisconnected(device) }
        }
        connectNote = IOBluetoothDevice.register(forConnectNotifications: listener, selector: #selector(DeviceBatteryListener.deviceConnected(_:device:)))
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        seeded = false
        refresh()
    }

    private func end() {
        guard running else { return }
        running = false
        timer?.invalidate()
        timer = nil
        retryTask?.cancel()
        retryTask = nil
        connectNote?.unregister()
        connectNote = nil
        for note in disconnectNotes.values { note.unregister() }
        disconnectNotes = [:]
        listener.onConnect = nil
        listener.onDisconnect = nil
        tracker = DeviceBatteryTracker()
        devices = []
        dismissBanner()
    }

    private func deviceConnected(_ device: IOBluetoothDevice) {
        guard running else { return }
        if let address = device.addressString {
            let id = DeviceBattery.normalize(address: address)
            tracker.connected(id)
            disconnectNotes[id]?.unregister()
            disconnectNotes[id] = device.register(forDisconnectNotification: listener, selector: #selector(DeviceBatteryListener.deviceDisconnected(_:device:)))
        }
        // Levels usually show up a few seconds after the connection.
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            for delay in [1.0, 2.0, 3.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    private func deviceDisconnected(_ device: IOBluetoothDevice) {
        guard running, let address = device.addressString else { return }
        let id = DeviceBattery.normalize(address: address)
        disconnectNotes[id]?.unregister()
        disconnectNotes[id] = nil
        tracker.disconnected(id)
        devices.removeAll { $0.id == id }
        if banner?.id == id { dismissBanner() }
    }

    private func refresh() {
        guard running else { return }
        let all = DeviceBattery.merge(bluetooth: DeviceBatterySource.bluetoothDevices(), hid: DeviceBatterySource.hidDevices())
        let alerts = tracker.process(all, firstPass: !seeded)
        seeded = true
        let shown = all.filter(\.hasBattery)
        if shown != devices { devices = shown }
        if let alert = alerts.last { show(alert) }
    }

    private func show(_ device: DeviceBattery) {
        bannerTask?.cancel()
        EverydayAlertStore.shared.dismissBanner()
        withAnimation(Self.animation) { banner = device }
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.dismissBanner()
        }
    }
}
