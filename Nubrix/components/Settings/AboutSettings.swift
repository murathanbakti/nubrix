import SwiftUI

struct AboutSettings: View {
    @State private var showBuildNumber = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    if showBuildNumber {
                        Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                            .foregroundStyle(.secondary)
                    }
                    Text(Bundle.main.releaseVersionNumber ?? "unknown")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        showBuildNumber.toggle()
                    }
                }
            }

            UpdatesSettingsSection()

            Section {
                Text("Nubrix is based on boring.notch by TheBoredTeam (GPL-3.0).")
                Text("License: GNU General Public License v3.0")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Credits")
            }

            HStack(spacing: 30) {
                Spacer(minLength: 0)
                Button {
                    if let url = URL(string: "https://github.com/TheBoredTeam/boring.notch") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image("Github")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18)
                        Text("boring.notch on GitHub")
                    }
                    .contentShape(Rectangle())
                }
                Spacer(minLength: 0)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .settingsPage(.about)
    }
}
