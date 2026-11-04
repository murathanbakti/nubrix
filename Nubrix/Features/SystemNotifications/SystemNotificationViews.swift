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
                .foregroundStyle(.white)
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
    static let bodyColor = Color.white.opacity(0.72)
    static let metaColor = Color.white.opacity(0.45)
}

private struct SystemNotificationCountCapsule: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.white.opacity(0.2)))
            .fixedSize()
    }
}

struct SystemNotificationBannerView: View {
    @EnvironmentObject var vm: NubrixViewModel
    @Default(.systemNotificationsShowBody) var showBody
    @Default(.systemNotificationStyle) var style
    let banner: SystemNotificationBanner

    private var detail: String { systemNotificationDetail(banner, showBody: showBody) }

    var body: some View {
        Group {
            if style == .dropDown {
                dropDownHeader
            } else {
                inlineHeader
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    private var inlineHeader: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                SystemNotificationAppIcon(bundleID: banner.bundleID)
                    .frame(width: 16, height: 16)
                Text(banner.title)
                    .font(SystemNotificationType.title)
                    .foregroundStyle(.white)
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
                .foregroundStyle(SystemNotificationType.bodyColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 170, alignment: .trailing)
        }
    }

    /// App name on the left, "now" or the count on the right; the text is in the card below.
    private var dropDownHeader: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                SystemNotificationAppIcon(bundleID: banner.bundleID, fallbackSize: 11)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(banner.appName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.leading, 4)
            .frame(width: 150, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            Group {
                if banner.count > 1 {
                    SystemNotificationCountCapsule(count: banner.count)
                } else {
                    Text("now")
                        .font(SystemNotificationType.meta)
                        .foregroundStyle(SystemNotificationType.metaColor)
                }
            }
            .padding(.trailing, 4)
            .frame(width: 150, alignment: .trailing)
        }
    }
}

/// The card under the notch for the drop-down style.
struct SystemNotificationDropBody: View {
    @EnvironmentObject var vm: NubrixViewModel
    @Default(.systemNotificationsShowBody) var showBody
    let banner: SystemNotificationBanner

    private var contentWidth: CGFloat { 300 + vm.closedNotchSize.width + 10 - 28 }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    SystemNotificationGlowIcon(bundleID: banner.bundleID, size: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(banner.title)
                                .font(SystemNotificationType.title)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 6)
                            Text(banner.count > 1 ? "+\(banner.count - 1) · now" : "now")
                                .font(SystemNotificationType.meta)
                                .foregroundStyle(SystemNotificationType.metaColor)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        Text(systemNotificationDetail(banner, showBody: showBody))
                            .font(SystemNotificationType.body)
                            .foregroundStyle(SystemNotificationType.bodyColor)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(width: contentWidth, alignment: .leading)

            if banner.count > 1 {
                VStack(spacing: 3) {
                    behindCard(widthFactor: 0.92, opacity: 0.08)
                    behindCard(widthFactor: 0.84, opacity: 0.05)
                }
                .frame(width: contentWidth + 28)
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, banner.count > 1 ? 6 : 12)
        .transition(.asymmetric(insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity), removal: .opacity))
    }

    private func behindCard(widthFactor: CGFloat, opacity: Double) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(opacity))
                .frame(width: geo.size.width * widthFactor, height: 4)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 4)
    }
}

struct SystemNotificationSettingsSection: View {
    @ObservedObject var store = SystemNotificationStore.shared
    @ObservedObject var inbox = NubrixInbox.shared
    @Default(.systemNotificationsEnabled) var enabled
    @Default(.systemNotificationApps) var allowedApps
    @Default(.systemNotificationStyle) var style
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
            Picker("Style", selection: $style) {
                ForEach(SystemNotificationStyle.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            Defaults.Toggle(key: .systemNotificationsShowBanner) {
                Text("Show a card when a notification arrives")
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
            SettingsFooter("Cards drop from the notch for a few seconds. Everything also stays in the Notifications tab.")
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
