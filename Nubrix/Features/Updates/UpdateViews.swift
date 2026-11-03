import AppKit
import SwiftUI

struct UpdatesSettingsSection: View {
    @ObservedObject private var store = UpdateStore.shared

    var body: some View {
        Section {
            if store.buildKind.updatesEnabled {
                releaseRows
            } else {
                unavailableRows
            }
        } header: {
            Text("Updates")
        } footer: {
            if store.buildKind.updatesEnabled {
                Text("Off until you turn it on. Nubrix then asks github.com/murathanbakti/nubrix for a signed update feed once a day. An update is installed only if its EdDSA signature and Apple Developer ID signature check out. Installed with Homebrew? brew upgrade --cask nubrix keeps working too.")
            }
        }
    }

    @ViewBuilder
    private var releaseRows: some View {
        Toggle("Check for updates automatically", isOn: Binding(
            get: { store.automaticallyChecks },
            set: { store.setAutomaticallyChecks($0) }
        ))
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Install updates automatically", isOn: Binding(
                get: { store.automaticallyInstalls },
                set: { store.setAutomaticallyInstalls($0) }
            ))
            .disabled(!store.automaticallyChecks)
            Text("Downloads in the background and installs when you quit Nubrix.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let reminder = store.reminder {
            HStack {
                Text(reminder.readyToInstall ? "Nubrix \(reminder.version) is ready to install" : "Nubrix \(reminder.version) is available")
                Spacer()
                Button("Show Update…") { store.checkNow() }
                    .disabled(!store.canCheckForUpdates)
            }
        }
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                Group {
                    if let lastCheck = store.lastCheck {
                        Text("Last checked ") + Text(lastCheck, style: .relative) + Text(" ago")
                    } else {
                        Text("Never checked")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Check Now") { store.checkNow() }
                .disabled(!store.canCheckForUpdates)
        }
    }

    @ViewBuilder
    private var unavailableRows: some View {
        if let message = store.buildKind.message {
            Text(message)
        }
        if let command = store.buildKind.sourceCommand {
            HStack(alignment: .top) {
                Text(command)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
            }
        }
    }

    private var statusText: LocalizedStringKey {
        switch store.status {
        case .idle: "Version \(Bundle.main.releaseVersionNumber ?? "unknown") (\(Bundle.main.buildVersionNumber ?? "?"))"
        case .upToDate: "Nubrix is up to date"
        case .failed(let message): "Couldn't check: \(message)"
        }
    }
}

struct UpdateMenuItems: View {
    @ObservedObject private var store = UpdateStore.shared

    var body: some View {
        if store.buildKind.updatesEnabled {
            if let reminder = store.reminder {
                Button(reminder.readyToInstall ? "Restart to Update Nubrix \(reminder.version)…" : "Update to Nubrix \(reminder.version)…") {
                    store.checkNow()
                }
            }
            Button("Check for Updates…") { store.checkNow() }
                .disabled(!store.canCheckForUpdates)
            Divider()
        }
    }
}
