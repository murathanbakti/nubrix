import AppKit
import CoreAudio
import CoreMediaIO
import DiskArbitration
import Foundation
import Network

/// One source of everyday alerts. Started only while its setting is on.
@MainActor
protocol EverydayWatcher: AnyObject {
    func start(emit: @escaping (EverydayAlert) -> Void)
    func stop()
}

// MARK: - CoreAudio helpers

enum CoreAudioReader {
    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var addr = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    static func defaultDevice(input: Bool) -> AudioObjectID? {
        let selector = input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        guard let id = uint32(AudioObjectID(kAudioObjectSystemObject), selector), id != kAudioObjectUnknown else { return nil }
        return id
    }

    static func defaultOutput() -> SoundDevice? {
        guard let id = defaultDevice(input: false) else { return nil }
        let uid = string(id, kAudioDevicePropertyDeviceUID) ?? String(id)
        let name = string(id, kAudioObjectPropertyName) ?? "your speakers"
        return SoundDevice(uid: uid, name: name, transport: uint32(id, kAudioDevicePropertyTransportType) ?? 0)
    }

    static func micIsRunning() -> Bool {
        guard let id = defaultDevice(input: true) else { return false }
        return (uint32(id, kAudioDevicePropertyDeviceIsRunningSomewhere) ?? 0) != 0
    }

    /// Name of an app that is recording right now (macOS 14.2 and later).
    static func appUsingMic() -> String? {
        guard #available(macOS 14.2, *) else { return nil }
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return nil }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &objects) == noErr else { return nil }
        let ownID = Bundle.main.bundleIdentifier
        for object in objects {
            guard (uint32(object, kAudioProcessPropertyIsRunningInput) ?? 0) != 0 else { continue }
            let bundleID = string(object, kAudioProcessPropertyBundleID) ?? ""
            if bundleID == ownID { continue }
            let pid = pid_t(bitPattern: uint32(object, kAudioProcessPropertyPID) ?? 0)
            if let name = appName(bundleID: bundleID, pid: pid) { return name }
        }
        return nil
    }

    private static func appName(bundleID: String, pid: pid_t) -> String? {
        let apps = NSWorkspace.shared.runningApplications
        if let app = apps.first(where: { $0.processIdentifier == pid && $0.activationPolicy == .regular }), let name = app.localizedName {
            return name
        }
        // Helpers (browsers, Zoom) belong to a main app whose id is a prefix of theirs.
        let owner = apps
            .filter { $0.activationPolicy == .regular && !($0.bundleIdentifier ?? "").isEmpty && bundleID.hasPrefix($0.bundleIdentifier ?? "\u{0}") }
            .max { ($0.bundleIdentifier ?? "").count < ($1.bundleIdentifier ?? "").count }
        if let name = owner?.localizedName { return name }
        if let name = NSRunningApplication(processIdentifier: pid)?.localizedName { return MicCameraTracker.cleanAppName(name) }
        return nil
    }
}

/// Keeps CoreAudio listeners so they can be removed again.
final class AudioListeners {
    private var entries: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    func add(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, handler: @escaping () -> Void) {
        var addr = CoreAudioReader.address(selector)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        guard AudioObjectAddPropertyListenerBlock(object, &addr, DispatchQueue.main, block) == noErr else { return }
        entries.append((object, addr, block))
    }

    func removeAll() {
        for (object, address, block) in entries {
            var addr = address
            AudioObjectRemovePropertyListenerBlock(object, &addr, DispatchQueue.main, block)
        }
        entries = []
    }

    deinit { removeAll() }
}

// MARK: - Sound output

@MainActor
final class SoundOutputWatcher: EverydayWatcher {
    private var tracker = SoundOutputTracker()
    private let listeners = AudioListeners()
    private var task: Task<Void, Never>?
    private var emit: ((EverydayAlert) -> Void)?

    func start(emit: @escaping (EverydayAlert) -> Void) {
        stop()
        self.emit = emit
        tracker = SoundOutputTracker()
        tracker.observe(CoreAudioReader.defaultOutput(), at: Date())
        listeners.add(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
    }

    func stop() {
        listeners.removeAll()
        task?.cancel()
        task = nil
        emit = nil
    }

    private func changed() {
        tracker.observe(CoreAudioReader.defaultOutput(), at: Date())
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(SoundOutputTracker.debounce + 0.05))
            guard !Task.isCancelled, let self else { return }
            if let device = self.tracker.settle(at: Date()) { self.emit?(device.alert) }
        }
    }
}

// MARK: - Drives

@MainActor
final class DriveWatcher: EverydayWatcher {
    private static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
        .volumeIsLocalKey, .volumeIsBrowsableKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
    ]

    private var tracker = DriveTracker()
    private var tokens: [NSObjectProtocol] = []

    static func read(_ url: URL) -> DriveVolume? {
        guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        return DriveVolume(
            path: url.path,
            name: v.volumeName ?? url.lastPathComponent,
            isInternal: v.volumeIsInternal ?? false,
            isRemovable: v.volumeIsRemovable ?? false,
            isEjectable: v.volumeIsEjectable ?? false,
            isLocal: v.volumeIsLocal ?? true,
            isBrowsable: v.volumeIsBrowsable ?? true,
            isDiskImage: diskImage(url),
            total: v.volumeTotalCapacity.map(Int64.init),
            free: v.volumeAvailableCapacity.map(Int64.init))
    }

    private static func diskImage(_ url: URL) -> Bool {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
              let info = DADiskCopyDescription(disk) as? [String: Any] else { return false }
        return DriveVolume.isDiskImage(
            protocolName: info[kDADiskDescriptionDeviceProtocolKey as String] as? String,
            model: info[kDADiskDescriptionDeviceModelKey as String] as? String)
    }

    private static func volumeURL(_ note: Notification) -> URL? {
        if let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL { return url }
        if let path = note.userInfo?["NSDevicePath"] as? String { return URL(fileURLWithPath: path) }
        return nil
    }

    func start(emit: @escaping (EverydayAlert) -> Void) {
        stop()
        tracker = DriveTracker()
        let existing = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Self.keys, options: [.skipHiddenVolumes]) ?? []
        tracker.seed(existing.compactMap(Self.read))

        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            guard let url = Self.volumeURL(note) else { return }
            MainActor.assumeIsolated {
                guard let self, let volume = Self.read(url), let alert = self.tracker.mounted(volume) else { return }
                emit(alert)
            }
        })
        tokens.append(center.addObserver(forName: NSWorkspace.willUnmountNotification, object: nil, queue: .main) { [weak self] note in
            guard let url = Self.volumeURL(note) else { return }
            MainActor.assumeIsolated {
                if let self, let volume = Self.read(url) { self.tracker.willUnmount(volume) }
            }
        })
        tokens.append(center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] note in
            guard let url = Self.volumeURL(note) else { return }
            MainActor.assumeIsolated {
                if let self, let alert = self.tracker.unmounted(path: url.path) { emit(alert) }
            }
        })
    }

    func stop() {
        for token in tokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        tokens = []
    }
}

// MARK: - Microphone and camera

enum CameraReader {
    private static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    static func devices() -> [CMIOObjectID] {
        var addr = address(kCMIOHardwarePropertyDevices)
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == 0, size > 0 else { return [] }
        var list = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &list) == 0 else { return [] }
        return list
    }

    static func isRunning(_ device: CMIOObjectID) -> Bool {
        var addr = address(kCMIODevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value)
        return status == 0 && value != 0
    }

    static func anyRunning() -> Bool { devices().contains(where: isRunning) }

    /// Returns the listener so it can be removed.
    static func listen(_ object: CMIOObjectID, _ selector: Int, handler: @escaping () -> Void) -> (CMIOObjectID, CMIOObjectPropertyAddress, CMIOObjectPropertyListenerBlock)? {
        var addr = address(selector)
        let block: CMIOObjectPropertyListenerBlock = { _, _ in handler() }
        guard CMIOObjectAddPropertyListenerBlock(object, &addr, DispatchQueue.main, block) == 0 else { return nil }
        return (object, addr, block)
    }

    static func unlisten(_ entry: (CMIOObjectID, CMIOObjectPropertyAddress, CMIOObjectPropertyListenerBlock)) {
        var addr = entry.1
        CMIOObjectRemovePropertyListenerBlock(entry.0, &addr, DispatchQueue.main, entry.2)
    }
}

@MainActor
final class MicCameraWatcher: EverydayWatcher {
    private var tracker = MicCameraTracker()
    private let systemAudio = AudioListeners()
    private let inputAudio = AudioListeners()
    private var cameraListeners: [(CMIOObjectID, CMIOObjectPropertyAddress, CMIOObjectPropertyListenerBlock)] = []
    private var task: Task<Void, Never>?
    private var emit: ((EverydayAlert) -> Void)?

    func start(emit: @escaping (EverydayAlert) -> Void) {
        stop()
        self.emit = emit
        tracker = MicCameraTracker()
        _ = tracker.update(mic: CoreAudioReader.micIsRunning(), camera: CameraReader.anyRunning(),
                           cameraIsOurs: MirrorMode.shared.isActive, at: Date())
        systemAudio.add(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice) { [weak self] in
            MainActor.assumeIsolated {
                self?.listenToInput()
                self?.schedule()
            }
        }
        listenToInput()
        listenToCameras()
        if let entry = CameraReader.listen(CMIOObjectID(kCMIOObjectSystemObject), kCMIOHardwarePropertyDevices, handler: { [weak self] in
            MainActor.assumeIsolated {
                self?.listenToCameras()
                self?.schedule()
            }
        }) {
            systemCamera = entry
        }
    }

    private var systemCamera: (CMIOObjectID, CMIOObjectPropertyAddress, CMIOObjectPropertyListenerBlock)?

    func stop() {
        systemAudio.removeAll()
        inputAudio.removeAll()
        for entry in cameraListeners { CameraReader.unlisten(entry) }
        cameraListeners = []
        if let systemCamera { CameraReader.unlisten(systemCamera) }
        systemCamera = nil
        task?.cancel()
        task = nil
        emit = nil
    }

    private func listenToInput() {
        inputAudio.removeAll()
        guard let id = CoreAudioReader.defaultDevice(input: true) else { return }
        inputAudio.add(id, kAudioDevicePropertyDeviceIsRunningSomewhere) { [weak self] in
            MainActor.assumeIsolated { self?.schedule() }
        }
    }

    private func listenToCameras() {
        for entry in cameraListeners { CameraReader.unlisten(entry) }
        cameraListeners = CameraReader.devices().compactMap { device in
            CameraReader.listen(device, kCMIODevicePropertyDeviceIsRunningSomewhere) { [weak self] in
                MainActor.assumeIsolated { self?.schedule() }
            }
        }
    }

    /// Waits a moment so the microphone and camera starting together become one alert,
    /// and so macOS has listed the app that uses the microphone.
    private func schedule() {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self else { return }
            self.evaluate()
        }
    }

    private func evaluate() {
        let result = tracker.update(mic: CoreAudioReader.micIsRunning(), camera: CameraReader.anyRunning(),
                                    cameraIsOurs: MirrorMode.shared.isActive, at: Date())
        guard let result else { return }
        var alert = result.alert
        if result.mic { alert.detail = MicCameraTracker.detail(app: CoreAudioReader.appUsingMic()) }
        emit?(alert)
    }
}

// MARK: - Internet

@MainActor
final class InternetWatcher: EverydayWatcher {
    private var tracker = InternetTracker()
    private var monitor: NWPathMonitor?
    private var task: Task<Void, Never>?
    private var emit: ((EverydayAlert) -> Void)?

    func start(emit: @escaping (EverydayAlert) -> Void) {
        stop()
        self.emit = emit
        tracker = InternetTracker()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.changed(satisfied: satisfied) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "dev.nubrix.everyday.internet"))
        self.monitor = monitor
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        task?.cancel()
        task = nil
        emit = nil
    }

    private func changed(satisfied: Bool) {
        guard monitor != nil else { return }
        task?.cancel()
        if let event = tracker.update(satisfied: satisfied, at: Date()) { emit?(event.alert) }
        guard !satisfied else { return }
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(InternetTracker.offlineDelay + 0.05))
            guard !Task.isCancelled, let self else { return }
            if let event = self.tracker.settle(at: Date()) { self.emit?(event.alert) }
        }
    }
}
