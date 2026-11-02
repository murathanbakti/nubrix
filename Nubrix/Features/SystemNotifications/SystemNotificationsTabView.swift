import AppKit
import Defaults
import SwiftUI

struct SystemNotificationsTabView: View {
    @ObservedObject var store = SystemNotificationStore.shared
    @Default(.systemNotificationsShowBody) var showBody
    @State private var filter: String?

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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.history.isEmpty {
                emptyState
            } else {
                topRow
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(records) { record in
                            SystemNotificationRow(record: record, store: store, showBody: showBody)
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
                Button("Grant Access…") { FullDiskAccessGuide.begin() }
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

struct SystemNotificationRow: View {
    let record: SystemNotificationRecord
    let store: SystemNotificationStore
    let showBody: Bool
    @State private var hovering = false

    private var message: String {
        if showBody {
            let text = [record.subtitle, record.body].filter { !$0.isEmpty }.joined(separator: " ")
            return text.isEmpty ? record.appName : text
        }
        return record.subtitle.isEmpty ? record.appName : record.subtitle
    }

    var body: some View {
        Button {
            store.open(bundleID: record.bundleID)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    (Text(record.title).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                        + Text(" · \(record.appName)").font(.system(size: 12)).foregroundColor(.gray))
                        .lineLimit(1)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                if hovering {
                    Button {
                        withAnimation(.smooth) { store.removeRecord(record.id) }
                    } label: {
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
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hovering ? 0.1 : 0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
