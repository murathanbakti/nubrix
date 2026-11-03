import Defaults
import SwiftUI

struct AdvancedSettings: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .hideTitleBar) {
                    Text("Hide title bar")
                }
                Defaults.Toggle(key: .showOnLockScreen) {
                    Text("Show notch on lock screen")
                }
                Defaults.Toggle(key: .hideFromScreenRecording) {
                    Text("Hide from screen recording")
                }
            } header: {
                Text("Window behavior")
            }
        }
        .settingsPage(.advanced)
    }
}
