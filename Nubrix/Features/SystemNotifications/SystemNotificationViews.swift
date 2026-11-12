import AppKit
import Defaults
import SwiftUI

private func systemNotificationDetail(_ banner: SystemNotificationBanner, showBody: Bool) -> String {
    if showBody, !banner.body.isEmpty { return banner.body }
    if !banner.subtitle.isEmpty { return banner.subtitle }
    return banner.appName
}

/// The sending app's icon, or a plain badge when it has none.
private struct SystemNotificationAppIcon: View {
    @Environment(\.nubrixPalette) private var palette
    @ObservedObject var store = SystemNotificationStore.shared
    let bundleID: String
    var fallbackSize: CGFloat = 13

    var body: some View {
        if let image = store.icon(for: bundleID) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.badge")
                .font(.system(size: fallbackSize, weight: .semibold))
                .foregroundStyle(palette.foreground)
        }
    }
}

/// App icon with a soft glow in the icon's own color behind it.
struct SystemNotificationGlowIcon: View {
    let bundleID: String
    var size: CGFloat = 32
    var glow = true
    @State private var color: Color?

    var body: some View {
        SystemNotificationAppIcon(bundleID: bundleID, fallbackSize: size * 0.7)
            .frame(width: size, height: size)
            .background {
                if glow, let color {
                    Circle()
                        .fill(color)
                        .opacity(0.35)
                        .frame(width: 44, height: 44)
                        .blur(radius: 14)
                }
            }
            .task(id: bundleID) {
                guard glow, let ns = await SystemNotificationStore.shared.glowColor(for: bundleID) else { return }
                color = Color(nsColor: ns)
            }
    }
}

enum SystemNotificationType {
    static let title = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 12, weight: .regular)
    static let meta = Font.system(size: 11, weight: .medium)
    static func bodyColor(_ palette: ThemePalette) -> Color { palette.foreground.opacity(0.72) }
    static func metaColor(_ palette: ThemePalette) -> Color { palette.foreground.opacity(0.45) }
}

private struct SystemNotificationCountCapsule: View {
    @Environment(\.nubrixPalette) private var palette
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(palette.foreground.opacity(0.2)))
            .fixedSize()
    }
}

struct SystemNotificationBannerView: View {
    @Environment(\.nubrixPalette) private var palette
    @EnvironmentObject var vm: NubrixViewModel
    @Default(.systemNotificationsShowBody) var showBody
    let banner: SystemNotificationBanner

    private var detail: String { systemNotificationDetail(banner, showBody: showBody) }

    var body: some View {
        inlineHeader
            .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    private var inlineHeader: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                SystemNotificationAppIcon(bundleID: banner.bundleID)
                    .frame(width: 16, height: 16)
                Text(banner.title)
                    .font(SystemNotificationType.title)
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if banner.count > 1 {
                    SystemNotificationCountCapsule(count: banner.count)
                }
            }
            .frame(maxWidth: 140, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            Text(detail)
                .font(SystemNotificationType.body)
                .foregroundStyle(SystemNotificationType.bodyColor(palette))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 170, alignment: .trailing)
        }
    }

}

struct SystemNotificationSettingsSection: View {
    @ObservedObject var store = SystemNotificationStore.shared
    @ObservedObject var inbox = NubrixInbox.shared
    @Default(.systemNotificationsEnabled) var enabled
    @Default(.systemNotificationApps) var allowedApps
    @Default(.systemNotificationGrouping) var grouping
    @ObservedObject var badges = DockBadgeStore.shared
    @Default(.dockBadgesEnabled) var badgesEnabled
    @State private var suggested: [String] = []

    private var rows: [String] {
        DockBadgeAppList.rows(
            known: store.knownApps,
            allowed: allowedApps,
            running: badgesEnabled ? suggested : [],
            defaults: badgesEnabled || store.knownApps.isEmpty ? DockBadgeAppList.defaults : [],
            ownBundleID: Bundle.main.bundleIdentifier,
            isInstalled: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        )
            .filter { id in
                store.knownApps.contains(id) || NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
            }
            .sorted { store.appName(for: $0).localizedCaseInsensitiveCompare(store.appName(for: $1)) == .orderedAscending }
    }

    var body: some View {
        Group {
            otherAppsSection
            if enabled { lookSection }
        }
        .onChange(of: enabled) { _, on in
            if !on {
                inbox.markRead(.system)
                FullDiskAccessGuide.close()
            }
            store.settingChanged()
            if on {
                store.refreshApps()
                FullDiskAccessGuide.begin()
            }
        }
        .onAppear {
            if enabled { store.refreshApps() }
            if badgesEnabled { suggested = badges.suggestedApps() }
        }
        .onChange(of: badgesEnabled) { _, on in
            if on { suggested = badges.suggestedApps() }
            badges.refresh()
        }
    }

    private var lookSection: some View {
        Section {
            Defaults.Toggle(key: .systemNotificationsShowBanner) {
                Text("Show a banner when a notification arrives")
            }
            Defaults.Toggle(key: .systemNotificationsShowBody) {
                Text("Show message text")
            }
            Defaults.Toggle(key: .systemNotificationsSkipFrontmost) {
                Text("Skip notifications from the app in front")
            }
            Picker("Group in the notch", selection: $grouping) {
                ForEach(SystemNotificationGrouping.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            Defaults.Toggle(key: .systemNotificationsCollapseGroups) {
                Text("Start groups collapsed")
            }
        } header: {
            Text("How they look")
        } footer: {
            SettingsFooter("Banners show beside the notch for a few seconds. Everything also stays in the Notifications tab.")
        }
    }

    private var otherAppsSection: some View {
        Section {
            Defaults.Toggle(key: .systemNotificationsEnabled) {
                Text("Show notifications from other apps")
            }
            Defaults.Toggle(key: .dockBadgesEnabled) {
                Text("Show unread counts")
            }
            if badgesEnabled && badges.status == .unavailable {
                Label("Unread counts are not available on this macOS version", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.secondary)
            }
            if enabled {
                statusRow
            }
            if enabled || badgesEnabled {
                ForEach(rows, id: \.self) { bundleID in
                    appRow(bundleID)
                }
                HStack {
                    Spacer()
                    Button("Refresh") {
                        if enabled { store.refreshApps() }
                        if badgesEnabled { suggested = badges.suggestedApps() }
                        badges.refresh()
                    }
                }
            }
        } header: {
            Text("Other apps")
        } footer: {
            SettingsFooter(
                "Only the apps you tick are read, and nothing is written to disk or sent anywhere. Unread counts show the number on each ticked app's Dock icon.",
                link: ("Learn more", SettingsLinks.notificationsGuide)
            )
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch store.status {
        case .ready:
            Label {
                Text("Ready. New notifications from the apps you tick appear in the notch.")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if rows.isEmpty {
                Text("Apps appear here after they post a notification. Click Refresh to update the list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .noAccess:
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
                Text("Nubrix needs Full Disk Access to read notifications.")
                Spacer()
                if !badgesEnabled {
                    Button("Use unread counts instead") { Defaults[.dockBadgesEnabled] = true }
                }
                Button("Grant access…") { FullDiskAccessGuide.begin() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(10)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
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
            if badgesEnabled, let badge = badges.badge(for: bundleID) {
                DockBadgeCountCapsule(text: badge.label, foreground: .primary, fill: Color.secondary.opacity(0.2))
            }
        }
    }
}
