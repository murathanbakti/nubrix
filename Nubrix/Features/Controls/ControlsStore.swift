import AppKit
import Combine
import CoreAudio
import Foundation
import IOBluetooth

struct ControlsBluetoothDevice: Identifiable, Equatable, Sendable {
    /// Address as reported by IOBluetooth.
    let id: String
    var name: String
    var symbol: String
    var connected: Bool
    /// Levels of the parts (L, R, Case, or one level). Empty when none can be read.
    var battery: [ControlsBatteryPart] = []
}

/// State of the Controls tab. Listens only while the tab is on screen.
@MainActor
final class ControlsStore: ObservableObject {
    static let shared = ControlsStore()

    @Published private(set) var outputs: [AudioDeviceInfo] = []
    @Published private(set) var inputs: [AudioDeviceInfo] = []
    @Published private(set) var currentOutput: AudioObjectID?
    @Published private(set) var currentInput: AudioObjectID?
    @Published private(set) var inputVolume: Float?
    @Published private(set) var bluetoothOn = false
    @Published private(set) var bluetooth: [ControlsBluetoothDevice] = []
    @Published private(set) var drives: [DriveVolume] = []
    @Published private(set) var busy: Set<String> = []
    /// Bluetooth power is being switched.
    @Published private(set) var bluetoothPowerBusy = false
    /// False when the helper can't switch Bluetooth; the quick toggle then opens Bluetooth settings.
    @Published private(set) var bluetoothSwitchable = true
    @Published private(set) var wifi = WiFiState()
    /// Whether macOS shows Wi-Fi network names to Nubrix (Location access).
    @Published private(set) var locationStatus: PermissionStatus = .notDetermined
    /// The network being joined, or "" while the power switch is working.
    @Published private(set) var wifiBusy: String?
    @Published private(set) var wifiMessage: String?

    private let listeners = AudioListeners()
    private var mountTokens: [NSObjectProtocol] = []
    private var timer: Timer?
    private var running = false
    private var micMemory: [AudioObjectID: Float] = [:]
    private var bluetoothReading = false
    private var wifiReading = false
    private var wifiForceAgain = false
    private var wifiVisible = false
    private let wifiReader = WiFiReader()
    private let wifiQueue = DispatchQueue(label: "dev.nubrix.controls.wifi", qos: .userInitiated)
    private let bluetoothQueue = DispatchQueue(label: "dev.nubrix.controls.bluetooth", qos: .userInitiated)

    private static let driveKeys: [URLResourceKey] = [
        .volumeNameKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
        .volumeIsLocalKey, .volumeIsBrowsableKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
    ]

    // MARK: Start and stop

    func start() {
        guard !running else { return }
        running = true
        VolumeManager.shared.refresh()
        BrightnessManager.shared.refresh()
        KeyboardBacklightManager.shared.refresh()

        let system = AudioObjectID(kAudioObjectSystemObject)
        listeners.add(system, kAudioHardwarePropertyDevices) { [weak self] in
            MainActor.assumeIsolated { self?.refreshAudio() }
        }
        listeners.add(system, kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            MainActor.assumeIsolated { self?.refreshAudio() }
        }
        listeners.add(system, kAudioHardwarePropertyDefaultInputDevice) { [weak self] in
            MainActor.assumeIsolated { self?.refreshAudio() }
        }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            mountTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDrives() }
            })
        }

        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshBluetooth()
                self?.refreshWiFi()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        refreshAudio()
        refreshDrives()
        refreshBluetooth()
        refreshWiFi()
        probeBluetoothSwitch()
    }

    func stop() {
        guard running else { return }
        running = false
        wifiVisible = false
        listeners.removeAll()
        for token in mountTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        mountTokens = []
        timer?.invalidate()
        timer = nil
    }

    // MARK: Sound

    func refreshAudio() {
        outputs = AudioDevices.devices(input: false)
        inputs = AudioDevices.devices(input: true)
        currentOutput = CoreAudioReader.defaultDevice(input: false)
        currentInput = CoreAudioReader.defaultDevice(input: true)
        inputVolume = currentInput.flatMap { AudioDevices.inputVolume($0) }
        VolumeManager.shared.refresh()
    }

    func select(_ device: AudioDeviceInfo, input: Bool) {
        AudioDevices.setDefault(device.id, input: input)
        if input { currentInput = device.id } else { currentOutput = device.id }
        refreshAudio()
    }

    func setInputVolume(_ value: Float) {
        guard let id = currentInput, inputVolume != nil else { return }
        AudioDevices.setInputVolume(id, value)
        inputVolume = max(0, min(1, value))
    }

    /// Mutes the current microphone (level 0, remembered) or brings the level back.
    func toggleMicMute() {
        guard let id = currentInput, let level = inputVolume else { return }
        let step = MicMute.toggle(level: level, remembered: micMemory[id])
        micMemory[id] = step.remembered
        setInputVolume(step.level)
    }

    // MARK: Wi-Fi

    /// Scans only run while the Wi-Fi list is showing.
    func setWiFiVisible(_ visible: Bool) {
        guard wifiVisible != visible else { return }
        wifiVisible = visible
        if visible { refreshWiFi() }
    }

    func openWiFiSettings() {
        guard let url = URL(string: WiFiMetrics.settingsURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func refreshWiFi(forceScan: Bool = false) {
        guard running else { return }
        if wifiReading {
            if forceScan { wifiForceAgain = true }
            return
        }
        wifiReading = true
        Task { @MainActor in
            let location = await Permissions.client.status(.location)
            if self.locationStatus != location { self.locationStatus = location }
            let scan = self.wifiVisible && location == .granted && self.wifiBusy == nil
            let reader = self.wifiReader
            self.wifiQueue.async {
                let state = reader.read(scan: scan, forceScan: forceScan)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self.wifiReading = false
                        if self.wifi != state { self.wifi = state }
                        if self.wifiForceAgain {
                            self.wifiForceAgain = false
                            self.refreshWiFi(forceScan: true)
                        }
                    }
                }
            }
        }
    }

    func setWiFiPower(_ on: Bool) {
        guard wifiBusy == nil else { return }
        wifiBusy = ""
        wifiMessage = nil
        let reader = wifiReader
        wifiQueue.async {
            let failed: Bool
            do { try reader.setPower(on); failed = false } catch { failed = true }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.wifiBusy = nil
                    if failed {
                        self.wifiMessage = "Can't switch Wi-Fi from here"
                        self.openWiFiSettings()
                    }
                    self.refreshWiFi(forceScan: true)
                }
            }
        }
    }

    func join(_ network: WiFiNetwork) {
        switch WiFiMetrics.joinAction(for: network) {
        case .openSettings:
            openWiFiSettings()
        case .join:
            guard wifiBusy == nil else { return }
            wifiBusy = network.ssid
            wifiMessage = nil
            let reader = wifiReader
            let ssid = network.ssid
            wifiQueue.async {
                let failed: Bool
                do { try reader.join(ssid: ssid); failed = false } catch { failed = true }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self.wifiBusy = nil
                        if failed { self.wifiMessage = "Couldn't join \(ssid)" }
                        self.refreshWiFi(forceScan: true)
                    }
                }
            }
        }
    }

    /// "Show network names": asks for Location once, or opens Privacy & Security when it was refused.
    func showNetworkNames() {
        Task { @MainActor in
            switch WiFiMetrics.namesAction(locationStatus) {
            case .ask:
                locationStatus = await Permissions.client.request(.location)
                refreshWiFi(forceScan: true)
            case .openSettings:
                Permissions.client.openSystemSettings(.location)
            case .none:
                break
            }
        }
    }

    // MARK: Drives

    func refreshDrives() {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Self.driveKeys, options: [.skipHiddenVolumes]) ?? []
        let list = urls.compactMap(DriveWatcher.read).filter(\.isUserVisible)
        if list != drives { drives = list }
    }

    /// Same eject as the drive alert, including the "couldn't eject" alert on failure.
    func eject(_ drive: DriveVolume) {
        EverydayAlertStore.shared.perform(.eject(drive.url))
    }

    // MARK: Bluetooth

    func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Asks the helper once per start whether it can read Bluetooth power (it is the process that may call
    /// the private IOBluetooth functions; the sandboxed app hangs on them).
    private func probeBluetoothSwitch() {
        Task { @MainActor in
            let state = await XPCHelperClient.shared.bluetoothPowerState()
            if bluetoothSwitchable != (state != nil) { bluetoothSwitchable = state != nil }
        }
    }

    /// Switches Bluetooth on or off through the helper; opens Bluetooth settings when that isn't possible.
    func toggleBluetoothPower() {
        guard !bluetoothPowerBusy else { return }
        guard bluetoothSwitchable else {
            openBluetoothSettings()
            return
        }
        let target = !bluetoothOn
        bluetoothPowerBusy = true
        Task { @MainActor in
            let ok = await XPCHelperClient.shared.setBluetoothPower(target)
            if !ok {
                bluetoothSwitchable = false
                bluetoothPowerBusy = false
                openBluetoothSettings()
                return
            }
            // The controller takes a moment to follow.
            for _ in 0..<8 {
                try? await Task.sleep(for: .milliseconds(400))
                refreshBluetooth()
                try? await Task.sleep(for: .milliseconds(100))
                if bluetoothOn == target { break }
            }
            bluetoothPowerBusy = false
        }
    }

    func refreshBluetooth() {
        guard !bluetoothReading else { return }
        bluetoothReading = true
        bluetoothQueue.async {
            let on = IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
            let devices = on ? Self.readBluetooth() : []
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.bluetoothReading = false
                    if self.bluetoothOn != on { self.bluetoothOn = on }
                    if self.bluetooth != devices { self.bluetooth = devices }
                }
            }
        }
    }

    func toggle(_ device: ControlsBluetoothDevice) {
        guard !busy.contains(device.id) else { return }
        busy.insert(device.id)
        let address = device.id
        let connect = !device.connected
        bluetoothQueue.async {
            if let target = IOBluetoothDevice(addressString: address) {
                if connect { _ = target.openConnection() } else { _ = target.closeConnection() }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.busy.remove(address)
                    self.refreshBluetooth()
                }
            }
        }
    }

    nonisolated private static func readBluetooth() -> [ControlsBluetoothDevice] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        let hid = DeviceBatterySource.hidDevices()
        var list: [ControlsBluetoothDevice] = []
        for device in paired {
            guard let address = device.addressString else { continue }
            let name = device.name ?? device.nameOrAddress ?? "Bluetooth device"
            let connected = device.isConnected()
            let kind = DeviceBatteryKind.detect(name: name, majorClass: Int(device.deviceClassMajor), minorClass: Int(device.deviceClassMinor))
            var battery: [ControlsBatteryPart] = []
            if connected {
                battery = DeviceBatterySource.snapshot(device).map(ControlsBattery.parts) ?? []
                if battery.isEmpty {
                    let id = DeviceBattery.normalize(address: address)
                    battery = hid.first { $0.id == id }.map(ControlsBattery.parts) ?? []
                }
            }
            list.append(ControlsBluetoothDevice(
                id: address, name: name, symbol: kind == .other ? "dot.radiowaves.left.and.right" : kind.symbol,
                connected: connected, battery: battery))
        }
        return list.sorted {
            if $0.connected != $1.connected { return $0.connected }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
