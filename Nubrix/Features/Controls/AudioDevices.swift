import CoreAudio
import Foundation

struct AudioDeviceInfo: Identifiable, Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transport: UInt32

    var isBuiltIn: Bool { transport == SoundDevice.builtIn }

    var symbol: String { SoundDevice(uid: uid, name: name, transport: transport).symbol }

    /// Second line in the list: how the device is connected.
    var kind: String { ControlsTransport.label(transport) }
}

/// Plain-words label for a Core Audio transport type.
enum ControlsTransport {
    static func label(_ transport: UInt32) -> String {
        switch transport {
        case SoundDevice.builtIn: "Built-in"
        case SoundDevice.bluetooth, SoundDevice.bluetoothLE: "Bluetooth"
        case SoundDevice.hdmi: "HDMI"
        case SoundDevice.displayPort: "DisplayPort"
        case SoundDevice.usb: "USB"
        case SoundDevice.airPlay: "AirPlay"
        case SoundDevice.code("virt"), SoundDevice.code("grup"): "Virtual"
        default: "Other"
        }
    }
}

/// Lists and switches the sound devices. Built on `CoreAudioReader`.
enum AudioDevices {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    static func devices(input: Bool) -> [AudioDeviceInfo] {
        var addr = CoreAudioReader.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        let list: [AudioDeviceInfo] = ids.compactMap { id in
            guard hasStreams(id, scope: scope) else { return nil }
            if (CoreAudioReader.uint32(id, kAudioDevicePropertyIsHidden) ?? 0) != 0 { return nil }
            let uid = CoreAudioReader.string(id, kAudioDevicePropertyDeviceUID) ?? String(id)
            let name = CoreAudioReader.string(id, kAudioObjectPropertyName) ?? "Unknown"
            return AudioDeviceInfo(id: id, uid: uid, name: name, transport: CoreAudioReader.uint32(id, kAudioDevicePropertyTransportType) ?? 0)
        }
        return list.sorted {
            if $0.isBuiltIn != $1.isBuiltIn { return $0.isBuiltIn }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func hasStreams(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var addr = CoreAudioReader.address(kAudioDevicePropertyStreams, scope: scope)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    static func setDefault(_ id: AudioObjectID, input: Bool) {
        var device = id
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        let selectors = input
            ? [kAudioHardwarePropertyDefaultInputDevice]
            : [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice]
        for selector in selectors {
            var addr = CoreAudioReader.address(selector)
            AudioObjectSetPropertyData(system, &addr, 0, nil, size, &device)
        }
    }

    // MARK: Input volume

    /// Main element first, then channels 1 and 2.
    private static func volumeElements(_ id: AudioObjectID) -> [UInt32] {
        [kAudioObjectPropertyElementMain, 1, 2].filter { element in
            var addr = volumeAddress(element)
            return AudioObjectHasProperty(id, &addr)
        }
    }

    private static func volumeAddress(_ element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeInput, mElement: element)
    }

    private static func isSettable(_ id: AudioObjectID, _ element: UInt32) -> Bool {
        var addr = volumeAddress(element)
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &addr, &settable) == noErr && settable.boolValue
    }

    /// `nil` when the device has no input volume that can be changed.
    static func inputVolume(_ id: AudioObjectID) -> Float? {
        let elements = volumeElements(id)
        let usable: [UInt32] = elements.contains(kAudioObjectPropertyElementMain) ? [kAudioObjectPropertyElementMain] : elements
        let readable = usable.filter { isSettable(id, $0) }
        guard !readable.isEmpty else { return nil }
        let values: [Float] = readable.compactMap { element in
            var addr = volumeAddress(element)
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr ? value : nil
        }
        guard !values.isEmpty else { return nil }
        return max(0, min(1, values.reduce(0, +) / Float(values.count)))
    }

    static func setInputVolume(_ id: AudioObjectID, _ value: Float) {
        let elements = volumeElements(id)
        let usable: [UInt32] = elements.contains(kAudioObjectPropertyElementMain) ? [kAudioObjectPropertyElementMain] : elements
        var level = max(0, min(1, value))
        for element in usable where isSettable(id, element) {
            var addr = volumeAddress(element)
            AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &level)
        }
    }
}
