import AppKit
import Defaults
import SwiftUI

struct SystemNotificationBannerView: View {
    @EnvironmentObject var vm: NubrixViewModel
    @ObservedObject var store = SystemNotificationStore.shared
    @Default(.systemNotificationsShowBody) var showBody
    let banner: SystemNotificationBanner

    private var detail: String {
        if showBody, !banner.body.isEmpty { return banner.body }
        if !banner.subtitle.isEmpty { return banner.subtitle }
        return banner.appName
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                appIcon
                    .frame(width: 16, height: 16)
                Text(banner.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: 140, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            Text(detail)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 170, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let image = store.icon(for: banner.bundleID) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.badge")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

struct SystemNotificationSettingsSection: View {
    @ObservedObject var store = SystemNotificationStore.shared
    @ObservedObject var inbox = NubrixInbox.shared
    @Default(.systemNotificationsEnabled) var enabled
    @Default(.systemNotificationApps) var allowedApps

    private var rows: [String] {
        Array(Set(store.knownApps).union(allowedApps))
            .sorted { store.appName(for: $0).localizedCaseInsensitiveCompare(store.appName(for: $1)) == .orderedAscending }
    }

    var body: some View {
        Section {
            Defaults.Toggle(key: .systemNotificationsEnabled) {
                Text("Show notifications from other apps")
            }
            if enabled {
                statusRow
                Defaults.Toggle(key: .systemNotificationsShowBody) {
                    Text("Show message text")
                }
                Defaults.Toggle(key: .systemNotificationsSkipFrontmost) {
                    Text("Skip notifications from the app in front")
                }
                ForEach(rows, id: \.self) { bundleID in
                    appRow(bundleID)
                }
                HStack {
                    Spacer()
                    Button("Refresh") { store.refreshApps() }
                }
            }
        } header: {
            Text("Other apps")
        } footer: {
            Text("Nubrix reads the macOS notification database to show new notifications from the apps you tick. This needs Full Disk Access for Nubrix (System Settings, Privacy & Security, Full Disk Access). Only apps you tick are read; nothing is stored, logged or sent anywhere, and notifications that arrived before you turned this on are not shown. Tip: set an app's alert style to None in System Settings, Notifications to see its notifications only in the notch.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .onChange(of: enabled) { _, on in
            if !on { inbox.markRead(.system) }
            store.settingChanged()
            if on { store.refreshApps() }
        }
        .onAppear {
            if enabled { store.refreshApps() }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch store.status {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        case .noAccess:
            HStack {
                Label("Full Disk Access needed", systemImage: "lock.fill")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Open Privacy & Security") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        case .unsupported:
            Label("Not supported on this macOS version", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.secondary)
        case .notFound:
            Label("Notification database not found", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        case .failed:
            Label("Could not read notifications", systemImage: "exclamationmark.circle")
                .foregroundStyle(.secondary)
        case .off, .waiting:
            Label("Checking", systemImage: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func appRow(_ bundleID: String) -> some View {
        HStack(spacing: 8) {
            if let image = store.icon(for: bundleID) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.badge")
                    .frame(width: 20, height: 20)
            }
            Toggle(store.appName(for: bundleID), isOn: Binding(
                get: { allowedApps.contains(bundleID) },
                set: { on in
                    if on {
                        if !allowedApps.contains(bundleID) { allowedApps.append(bundleID) }
                    } else {
                        allowedApps.removeAll { $0 == bundleID }
                    }
                }
            ))
        }
    }
}
