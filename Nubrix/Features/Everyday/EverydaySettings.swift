import Defaults
import SwiftUI

struct EverydaySettings: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .deviceBatteryEnabled) {
                    Text("Battery of AirPods and other devices")
                }
            } header: {
                Text("Devices")
            } footer: {
                SettingsFooter("Shows the battery when AirPods and other Bluetooth devices connect. macOS asks for Bluetooth access the first time.")
            }

            Section {
                Defaults.Toggle(key: .everydaySoundOutput) {
                    Text("Tell me where sound plays")
                }
            } header: {
                Text("Sound")
            } footer: {
                SettingsFooter("Shows a note when sound moves to headphones, speakers or a display.")
            }

            Section {
                Defaults.Toggle(key: .everydayDrives) {
                    Text("Drives and memory cards")
                }
            } header: {
                Text("Drives")
            } footer: {
                SettingsFooter("Shows when a drive is connected, with an Eject button, and when it is safe to unplug.")
            }

            Section {
                Defaults.Toggle(key: .everydayMicCamera) {
                    Text("Microphone and camera")
                }
            } header: {
                Text("Privacy")
            } footer: {
                SettingsFooter("Shows when an app starts using your microphone or camera. Nubrix never records anything.")
            }

            Section {
                Defaults.Toggle(key: .everydayInternet) {
                    Text("Internet connection")
                }
            } header: {
                Text("Internet")
            } footer: {
                SettingsFooter("Shows when you lose your internet connection and when it comes back.")
            }

            Section {
                Defaults.Toggle(key: .everydayScreenShare) {
                    Text("When your screen is shared")
                }
            } header: {
                Text("Screen sharing")
            } footer: {
                SettingsFooter("Shows when another app starts sharing or recording your screen, or when it is mirrored to an AirPlay display or TV. Nubrix only asks macOS whether someone is watching; it never captures the screen.")
            }
        }
        .settingsPage(.everyday)
    }
}
