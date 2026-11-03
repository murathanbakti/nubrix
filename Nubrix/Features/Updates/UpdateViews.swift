import AppKit
import SwiftUI

struct UpdatesSettingsSection: View {
    @ObservedObject private var store = UpdateStore.shared

    var body: some View {
        Section {
            if store.autoCheck == nil {
                askRow
            } else {
                Toggle("Check for updates once a day", isOn: autoCheckBinding)
            }
            statusRow
            switch store.state {
            case .available(let version):
                availableRows(version)
            case .skipped:
                Button("Show again") { store.unskip() }
            default:
                EmptyView()
            }
        } header: {
            Text("Updates")
        } footer: {
            Text("Asks api.github.com for the latest release, without your GitHub token. Nothing is downloaded or installed.")
        }
    }

    private var autoCheckBinding: Binding<Bool> {
        Binding(
            get: { store.autoCheck == true },
            set: { store.autoCheck = $0 }
        )
    }

    private var askRow: some View {
        HStack {
            Text("Check for new versions once a day?")
            Spacer()
            Button("Not now") { store.autoCheck = false }
            Button("Turn on") { store.autoCheck = true }
        }
    }

    private var statusRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                if let lastCheck = store.lastCheck {
                    (Text("Last checked ") + Text(lastCheck, style: .relative) + Text(" ago"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Check now") { store.checkNow() }
                .disabled(store.state == .checking)
        }
    }

    private var statusText: LocalizedStringKey {
        switch store.state {
        case .idle: store.lastCheck == nil ? "Never checked" : "Not checked since launch"
        case .checking: "Checking…"
        case .upToDate: "Nubrix is up to date"
        case .available(let version): "Version \(version.description) is available"
        case .skipped(let version): "Version \(version.description) skipped"
        case .failed(let failure): "Couldn't check: \(failure.message)"
        }
    }

    @ViewBuilder
    private func availableRows(_ version: ReleaseVersion) -> some View {
        let instructions = store.installKind.instructions
        VStack(alignment: .leading, spacing: 6) {
            Text(instructions.summary)
            HStack(alignment: .top) {
                Text(instructions.command)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(instructions.command, forType: .string)
                }
            }
        }
        HStack {
            if instructions.showsViewRelease {
                Button("View release") {
                    NSWorkspace.shared.open(UpdateLinks.releaseURL(for: version))
                }
            }
            Button("Skip this version") { store.skip() }
        }
        Text(instructions.hooksReminder)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }
}

struct UpdateMenuItems: View {
    @ObservedObject private var store = UpdateStore.shared

    var body: some View {
        if let version = store.availableVersion {
            Button("Update available: \(version.description)…") {
                SettingsNavigation.shared.open("About")
            }
        }
        if store.autoCheck == nil {
            Button("Turn on update checks…") {
                SettingsNavigation.shared.open("About")
            }
        }
        Button("Check for Updates…") {
            store.checkNow()
            SettingsNavigation.shared.open("About")
        }
        Divider()
    }
}
