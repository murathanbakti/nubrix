import AppKit
import Defaults
import SwiftUI

struct SystemNotificationsTabView: View {
    @ObservedObject var store = SystemNotificationStore.shared
    @Default(.systemNotificationsShowBody) var showBody
    @ObservedObject var badges = DockBadgeStore.shared
    @Default(.dockBadgesEnabled) var badgesEnabled
    @State private var filter: String?
    @Default(.systemNotificationGrouping) var grouping
    @Default(.systemNotificationsCollapseGroups) var collapseGroups
    /// Groups the user flipped away from the default (opened when collapsed by default, closed otherwise).
    @State private var flipped: Set<String> = []

    private var apps: [(id: String, name: String)] {
        var seen = Set<String>()
        var result: [(id: String, name: String)] = []
        for record in store.history where seen.insert(record.bundleID).inserted {
            result.append((record.bundleID, record.appName))
        }
        return result
    }

    private var activeFilter: String? {
        guard let filter, store.history.contains(where: { $0.bundleID == filter }) else { return nil }
        return filter
    }

    private var records: [SystemNotificationRecord] {
        guard let activeFilter else { return store.history }
        return store.history.filter { $0.bundleID == activeFilter }
    }

    private var stacks: [SystemNotificationStack] {
        SystemNotificationStack.stacks(from: records, grouping: grouping)
    }

    private func isExpanded(_ key: String) -> Bool {
        flipped.contains(key) == collapseGroups
    }

    private func toggle(_ key: String) {
        withAnimation(.smooth) {
            if !flipped.insert(key).inserted { flipped.remove(key) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.history.isEmpty {
                if !badges.summary.isEmpty {
                    DockBadgeRowsView()
                } else {
                    emptyState
                }
            } else {
                topRow
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(stacks) { stack in
                            SystemNotificationStackView(stack: stack, store: store, showBody: showBody,
                                                        isExpanded: isExpanded(stack.id)) { toggle(stack.id) }
                        }
                    }
                }
                .onChange(of: grouping) { _, _ in flipped = [] }
                .onChange(of: collapseGroups) { _, _ in flipped = [] }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 4)
    }

    private var topRow: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    chip("All", selected: activeFilter == nil, count: badges.summary.isEmpty ? nil : badges.summary.totalText) { filter = nil }
                    ForEach(apps, id: \.id) { app in
                        chip(app.name, selected: activeFilter == app.id, count: badges.badge(for: app.id)?.label) { filter = app.id }
                    }
                }
            }
            Spacer(minLength: 6)
            Button("Clear") { withAnimation(.smooth) { store.clearHistory() } }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .padding(.horizontal, 2)
    }

    private func chip(_ title: String, selected: Bool, count: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : Color.gray)
                    .lineLimit(1)
                if let count {
                    DockBadgeCountCapsule(text: count)
                }
            }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.14 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.status == .off && badgesEnabled {
            badgeOnlyEmpty
        } else {
            notificationsEmptyState
        }
    }

    private var badgeOnlyEmpty: some View {
        VStack(spacing: 4) {
            Image(systemName: "app.badge")
                .font(.title3)
                .foregroundStyle(.gray)
            Text("No unread messages")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Unread counts from the apps you pick appear here")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var notificationsEmptyState: some View {
        switch store.status {
        case .noAccess:
            VStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundStyle(.gray)
                Text("Needs Full Disk Access")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Button("Grant access…") { FullDiskAccessGuide.begin(origin: .notch) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                if !badgesEnabled {
                    Button("Use unread counts instead") { Defaults[.dockBadgesEnabled] = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready, .waiting:
            VStack(spacing: 4) {
                Image(systemName: "bell")
                    .font(.title3)
                    .foregroundStyle(.gray)
                Text("No notifications yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("New notifications from the apps you pick appear here")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var statusLabel: String {
        switch store.status {
        case .notFound: return "Notification database not found"
        case .unsupported: return "Not supported on this macOS version"
        case .failed: return "Couldn't read notifications"
        default: return "Notifications are off"
        }
    }
}

struct SystemNotificationStackView: View {
    let stack: SystemNotificationStack
    let store: SystemNotificationStore
    let showBody: Bool
    let isExpanded: Bool
    let toggle: () -> Void
    @State private var hovering = false

    private func removeStack() {
        withAnimation(.smooth) { store.removeRecords(stack.recordIDs) }
    }

    var body: some View {
        if let newest = stack.records.first {
            if stack.records.count == 1 {
                SystemNotificationRow(record: newest, store: store, showBody: showBody, inAppGroup: stack.isAppGroup) {
                    withAnimation(.smooth) { store.removeRecord(newest.id) }
                }
            } else if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    header(newest)
                    ForEach(stack.records) { record in
                        SystemNotificationRow(record: record, store: store, showBody: showBody, inAppGroup: stack.isAppGroup) {
                            withAnimation(.smooth) { store.removeRecord(record.id) }
                        }
                    }
                }
            } else {
                SystemNotificationRow(record: newest, store: store, showBody: showBody, inAppGroup: stack.isAppGroup, hiddenCount: stack.records.count - 1,
                                      toggle: toggle, remove: removeStack)
                .padding(.bottom, stack.records.count > 2 ? 8 : 4)
            }
        }
    }

    private func header(_ newest: SystemNotificationRecord) -> some View {
        HStack(spacing: 6) {
            SystemNotificationGlowIcon(bundleID: newest.bundleID, size: 20, glow: false)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(stack.isAppGroup || newest.title.isEmpty ? newest.appName : "\(newest.title) · \(newest.appName)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("\(stack.records.count)")
                .font(SystemNotificationType.meta)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.white.opacity(0.2)))
                .fixedSize()
            Spacer(minLength: 6)
            if hovering {
                ClearCircleButton(action: removeStack)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(systemNotificationAge(from: newest.date, to: context.date))
                    .font(SystemNotificationType.meta.monospacedDigit())
                    .foregroundStyle(SystemNotificationType.metaColor)
            }
            Button(action: toggle) {
                Text("Show less")
                    .font(SystemNotificationType.meta)
                    .foregroundStyle(SystemNotificationType.metaColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

struct ClearCircleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .help("Clear")
    }
}

struct SystemNotificationRow: View {
    let record: SystemNotificationRecord
    let store: SystemNotificationStore
    let showBody: Bool
    var inAppGroup = false
    var hiddenCount = 0
    var toggle: (() -> Void)?
    let remove: () -> Void
    @State private var hovering = false

    private var subtitleLine: String? {
        record.subtitle.isEmpty || record.subtitle == record.title ? nil : record.subtitle
    }

    private var messageLine: String? {
        if showBody, !record.body.isEmpty { return record.body }
        return subtitleLine == nil && !inAppGroup ? record.appName : nil
    }

    private var heading: Text {
        if record.title.isEmpty {
            return Text(record.appName).font(SystemNotificationType.title).foregroundColor(.white)
        }
        if inAppGroup {
            return Text(record.title).font(SystemNotificationType.title).foregroundColor(.white)
        }
        return Text(record.title).font(SystemNotificationType.title).foregroundColor(.white)
            + Text(" · \(record.appName)").font(SystemNotificationType.meta).foregroundColor(SystemNotificationType.metaColor)
    }

    var body: some View {
        Button {
            store.open(bundleID: record.bundleID)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    heading
                        .lineLimit(1)
                    if let subtitleLine {
                        Text(subtitleLine)
                            .font(SystemNotificationType.meta)
                            .foregroundStyle(SystemNotificationType.metaColor)
                            .lineLimit(1)
                    }
                    if let messageLine {
                        Text(messageLine)
                            .font(SystemNotificationType.body)
                            .foregroundStyle(SystemNotificationType.bodyColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if hiddenCount > 0, let toggle {
                        Button(action: toggle) {
                            HStack(spacing: 3) {
                                Text("+\(hiddenCount)")
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .font(SystemNotificationType.meta)
                            .foregroundStyle(SystemNotificationType.metaColor)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 6)
                if hovering {
                    ClearCircleButton(action: remove)
                } else {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(systemNotificationAge(from: record.date, to: context.date))
                            .font(SystemNotificationType.meta.monospacedDigit())
                            .foregroundStyle(SystemNotificationType.metaColor)
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.09 : 0.06))
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black))
            )
            .background(alignment: .bottom) {
                if hiddenCount > 0 {
                    ZStack {
                        if hiddenCount > 1 { edge(inset: 12, offset: 8, opacity: 0.03) }
                        edge(inset: 6, offset: 4, opacity: 0.045)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private func edge(inset: CGFloat, offset: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(opacity))
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black))
            .padding(.horizontal, inset)
            .offset(y: offset)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = store.icon(for: record.bundleID) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "app.badge")
                .font(.system(size: 14))
                .foregroundStyle(.gray)
                .frame(width: 20, height: 20)
        }
    }
}
