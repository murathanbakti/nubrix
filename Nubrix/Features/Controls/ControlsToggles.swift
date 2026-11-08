import CoreAudio
import Foundation

// MARK: - Quick toggles

enum ControlsToggleFill: Equatable {
    case accent, neutral, red
}

/// How one of the four round quick toggles looks and what its tooltip says.
struct ControlsToggleState: Equatable {
    var symbol: String
    var label: String
    var fill: ControlsToggleFill
    var help: String
}

enum ControlsToggles {
    /// Not an SF Symbol: the view draws the Bluetooth rune itself for this name.
    static let bluetoothGlyph = "bluetooth"

    static func wifi(available: Bool, powered: Bool) -> ControlsToggleState {
        guard available else {
            return ControlsToggleState(symbol: "wifi.slash", label: "Wi-Fi", fill: .neutral, help: "No Wi-Fi on this Mac")
        }
        return ControlsToggleState(
            symbol: powered ? "wifi" : "wifi.slash", label: "Wi-Fi",
            fill: powered ? .accent : .neutral,
            help: powered ? "Turn Wi-Fi off" : "Turn Wi-Fi on")
    }

    /// `switchable` is false when this Mac won't let Nubrix change Bluetooth power; the button then
    /// opens Bluetooth settings instead.
    static func bluetooth(on: Bool, switchable: Bool) -> ControlsToggleState {
        let help = switchable ? (on ? "Turn Bluetooth off" : "Turn Bluetooth on") : "Open Bluetooth settings"
        return ControlsToggleState(symbol: bluetoothGlyph, label: "Bluetooth", fill: on ? .accent : .neutral, help: help)
    }

    static func sound(muted: Bool) -> ControlsToggleState {
        ControlsToggleState(
            symbol: muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
            label: muted ? "Muted" : "Sound",
            fill: muted ? .red : .neutral,
            help: muted ? "Unmute" : "Mute")
    }

    static func mic(muted: Bool, settable: Bool) -> ControlsToggleState {
        ControlsToggleState(
            symbol: muted ? "mic.slash.fill" : "mic.fill",
            label: muted ? "Mic off" : "Mic",
            fill: muted ? .red : .neutral,
            help: settable ? (muted ? "Turn the microphone on" : "Turn the microphone off") : "This microphone's level can't be changed")
    }
}

// MARK: - Microphone mute

/// Muting the microphone sets its input volume to 0 and remembers the level to bring back.
enum MicMute {
    /// Level restored when nothing was remembered (the user dragged the slider to 0 themselves).
    static let fallbackLevel: Float = 0.75

    static func isMuted(_ level: Float?) -> Bool {
        guard let level else { return false }
        return level <= 0.005
    }

    /// The level to set and the level to remember afterwards.
    static func toggle(level: Float, remembered: Float?) -> (level: Float, remembered: Float?) {
        if isMuted(level) {
            let back = remembered.map { $0 > 0.005 ? $0 : fallbackLevel } ?? fallbackLevel
            return (back, nil)
        }
        return (0, level)
    }
}

// MARK: - Tabs

extension ControlsListTab {
    /// Drives is only offered while a drive is mounted.
    static func tabs(hasDrives: Bool) -> [ControlsListTab] {
        allCases.filter { $0 != .drives || hasDrives }
    }

    /// The saved tab, or Wi-Fi when it is Drives and nothing is mounted any more.
    static func effective(_ raw: String, hasDrives: Bool) -> ControlsListTab {
        let tab = resolve(raw)
        return tab == .drives && !hasDrives ? .wifi : tab
    }
}
