import AppKit
import Defaults
import SwiftUI

struct SystemNotificationsTabView: View {
    @ObservedObject var store = SystemNotificationStore.shared
    @Default(.systemNotificationsShowBody) var showBody
    @State private var filter: String?
    @State private var expanded: Set<String> = []

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
        var order: [String] = []
        var groups: [String: [SystemNotificationRecord]] = [:]
        for record in records {
            let key = record.conversationKey
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(record)
        }
        return order.map { SystemNotificationStack(id: $0, records: groups[$0] ?? []) }
    }

    private func toggle(_ key: String) {
        withAnimation(.smooth) {
            if !expanded.insert(key).inserted { expanded.remove(key) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.history.isEmpty {
                emptyState
            } else {
                topRow
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(stacks) { stack in
                            SystemNotificationStackView(stack: stack, store: store, showBody: showBody,
                                                        isExpanded: expanded.contains(stack.id)) { toggle(stack.id) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 4)
    }

    private var topRow: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    chip("All", selected: activeFilter == nil) { filter = nil }
                    ForEach(apps, id: \.id) { app in
                        chip(app.name, selected: activeFilter == app.id) { filter = app.id }
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

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.gray)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.14 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var emptyState: some View {
        switch store.status {
        case .noAccess:
            VStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundStyle(.gray)
                Text("Needs Full Disk Access")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Button("Grant Access…") { FullDiskAccessGuide.begin(origin: .notch) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
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

struct SystemNotificationStack: Identifiable {
    let id: String
    let records: [SystemNotificationRecord]
}

struct SystemNotificationStackView: View {
    let stack: SystemNotificationStack
    let store: SystemNotificationStore
    let showBody: Bool
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        if let newest = stack.records.first {
            if stack.records.count == 1 {
                SystemNotificationRow(record: newest, store: store, showBody: showBody) {
                    withAnimation(.smooth) { store.removeRecord(newest.id) }
                }
            } else if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    header(newest)
                    ForEach(stack.records) { record in
                        SystemNotificationRow(record: record, store: store, showBody: showBody) {
                            withAnimation(.smooth) { store.removeRecord(record.id) }
                        }
                    }
                }
            } else {
                SystemNotificationRow(record: newest, store: store, showBody: showBody, hiddenCount: stack.records.count - 1,
                                      toggle: toggle) {
                    withAnimation(.smooth) { store.removeConversation(stack.id) }
                }
                .padding(.bottom, stack.records.count > 2 ? 8 : 4)
            }
        }
    }

    private func header(_ newest: SystemNotificationRecord) -> some View {
        HStack(spacing: 6) {
            Text(newest.title.isEmpty ? newest.appName : "\(newest.title) · \(newest.appName)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.gray)
                .lineLimit(1)
            Spacer(minLength: 6)
            Button("Show less", action: toggle)
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.gray)
        }
        .padding(.horizontal, 4)
    }
}

struct SystemNotificationRow: View {
    let record: SystemNotificationRecord
    let store: SystemNotificationStore
    let showBody: Bool
    var hiddenCount = 0
    var toggle: (() -> Void)?
    let remove: () -> Void
    @State private var hovering = false

    private var subtitleLine: String? {
        record.subtitle.isEmpty || record.subtitle == record.title ? nil : record.subtitle
    }

    private var messageLine: String? {
        if showBody, !record.body.isEmpty { return record.body }
        return subtitleLine == nil ? record.appName : nil
    }

    private var heading: Text {
        if record.title.isEmpty {
            return Text(record.appName).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
        }
        return Text(record.title).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            + Text(" · \(record.appName)").font(.system(size: 12)).foregroundColor(.gray)
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
                            .font(.system(size: 10))
                            .foregroundStyle(.gray.opacity(0.8))
                            .lineLimit(1)
                    }
                    if let messageLine {
                        Text(messageLine)
                            .font(.system(size: 11))
                            .foregroundStyle(.gray)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if hiddenCount > 0, let toggle {
                        Button(action: toggle) {
                            HStack(spacing: 3) {
                                Text("+\(hiddenCount) more")
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.gray)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 6)
                if hovering {
                    Button(action: remove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.gray)
                    }
                    .buttonStyle(.plain)
                } else {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(Self.age(from: record.date, to: context.date))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.gray)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(hovering ? 0.1 : 0.06))
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black))
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
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(opacity))
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black))
            .padding(.horizontal, inset)
            .offset(y: offset)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = store.icon(for: record.bundleID) {
            Image(nsImage: image)
                .resizable()
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "app.badge")
                .font(.system(size: 14))
                .foregroundStyle(.gray)
                .frame(width: 20, height: 20)
        }
    }

    private static func age(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}
