import XCTest
@testable import Nubrix

final class ControlsTogglesTests: XCTestCase {
    func testMicMuteRemembersAndRestoresTheLevel() {
        let muted = MicMute.toggle(level: 0.6, remembered: nil)
        XCTAssertEqual(muted.level, 0)
        XCTAssertEqual(muted.remembered, 0.6)
        XCTAssertTrue(MicMute.isMuted(muted.level))

        let restored = MicMute.toggle(level: muted.level, remembered: muted.remembered)
        XCTAssertEqual(restored.level, 0.6)
        XCTAssertNil(restored.remembered)
    }

    func testMicUnmuteWithoutMemoryUsesTheFallback() {
        XCTAssertEqual(MicMute.toggle(level: 0, remembered: nil).level, MicMute.fallbackLevel)
        XCTAssertEqual(MicMute.toggle(level: 0, remembered: 0).level, MicMute.fallbackLevel)
    }

    func testMicMutedOnlyWhenTheLevelIsKnownAndZero() {
        XCTAssertFalse(MicMute.isMuted(nil))
        XCTAssertFalse(MicMute.isMuted(0.4))
        XCTAssertTrue(MicMute.isMuted(0))
    }

    func testDrivesTabHiddenWithoutDrives() {
        XCTAssertEqual(ControlsListTab.tabs(hasDrives: false).map(\.rawValue), ["Wi-Fi", "Bluetooth", "Output", "Input"])
        XCTAssertEqual(ControlsListTab.tabs(hasDrives: true).last, .drives)
    }

    func testSavedDrivesTabFallsBackToWiFiWhenNothingIsMounted() {
        XCTAssertEqual(ControlsListTab.effective("Drives", hasDrives: false), .wifi)
        XCTAssertEqual(ControlsListTab.effective("Drives", hasDrives: true), .drives)
        XCTAssertEqual(ControlsListTab.effective("Input", hasDrives: false), .input)
        XCTAssertEqual(ControlsListTab.effective("nonsense", hasDrives: true), .wifi)
    }

    func testWiFiToggle() {
        XCTAssertEqual(ControlsToggles.wifi(available: true, powered: true).fill, .accent)
        XCTAssertEqual(ControlsToggles.wifi(available: true, powered: true).symbol, "wifi")
        let off = ControlsToggles.wifi(available: true, powered: false)
        XCTAssertEqual(off.fill, .neutral)
        XCTAssertEqual(off.symbol, "wifi.slash")
        XCTAssertEqual(ControlsToggles.wifi(available: false, powered: true).fill, .neutral)
    }

    func testBluetoothToggle() {
        XCTAssertEqual(ControlsToggles.bluetooth(on: true, switchable: true).fill, .accent)
        XCTAssertEqual(ControlsToggles.bluetooth(on: false, switchable: true).fill, .neutral)
        XCTAssertEqual(ControlsToggles.bluetooth(on: true, switchable: true).help, "Turn Bluetooth off")
        XCTAssertEqual(ControlsToggles.bluetooth(on: false, switchable: false).help, "Open Bluetooth settings")
        XCTAssertEqual(ControlsToggles.bluetooth(on: true, switchable: true).symbol, ControlsToggles.bluetoothGlyph)
    }

    func testSoundAndMicToggles() {
        XCTAssertEqual(ControlsToggles.sound(muted: false).label, "Sound")
        XCTAssertEqual(ControlsToggles.sound(muted: false).fill, .neutral)
        let muted = ControlsToggles.sound(muted: true)
        XCTAssertEqual(muted.label, "Muted")
        XCTAssertEqual(muted.fill, .red)
        XCTAssertEqual(muted.symbol, "speaker.slash.fill")

        XCTAssertEqual(ControlsToggles.mic(muted: false, settable: true).label, "Mic")
        let micOff = ControlsToggles.mic(muted: true, settable: true)
        XCTAssertEqual(micOff.label, "Mic off")
        XCTAssertEqual(micOff.fill, .red)
        XCTAssertEqual(micOff.symbol, "mic.slash.fill")
    }
}
