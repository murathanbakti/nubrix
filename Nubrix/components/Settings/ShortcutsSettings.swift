import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettings: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle notch open", name: .toggleNotchOpen)
            } header: {
                Text("Notch")
            }
            Section {
                KeyboardShortcuts.Recorder("Toggle sneak peek", name: .toggleSneakPeek)
            } header: {
                Text("Media")
            } footer: {
                SettingsFooter("Sneak peek shows the title and artist under the notch for a few seconds.")
            }
            Section {
                KeyboardShortcuts.Recorder("Toggle Vitrin", name: .toggleVitrin)
            } header: {
                Text("Vitrin")
            }
            Section {
                KeyboardShortcuts.Recorder("Toggle mirror", name: .toggleMirror)
            } header: {
                Text("Mirror")
            }
            Section {
                KeyboardShortcuts.Recorder("Toggle calendar", name: .toggleCalendar)
            } header: {
                Text("Calendar")
            }
        }
        .settingsPage(.shortcuts)
    }
}
