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
    @EnvironmentObject var vm: NubrixViewModel
    @Default(.systemNotificationQuickReply) var quickReply
    @ObservedObject private var reply = NotificationReplyController.shared
    @FocusState private var focused: Bool
    @State private var hovering = false

    private var message: String {
        if showBody {
            let text = [record.subtitle, record.body].filter { !$0.isEmpty }.joined(separator: " ")
            return text.isEmpty ? record.appName : text
        }
        return record.subtitle.isEmpty ? record.appName : record.subtitle
    }

    private var heading: Text {
        if record.title.isEmpty {
            return Text(record.appName).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
        }
        return Text(record.title).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            + Text(" · \(record.appName)").font(.system(size: 12)).foregroundColor(.gray)
    }

    private var replying: Bool { reply.activeRecordID == record.id }
    private var target: String { record.title.isEmpty ? record.appName : record.title }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            summary
            if replying {
                replyArea
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hovering || replying ? 0.1 : 0.06)))
        .contentShape(Rectangle())
        .onTapGesture {
            if !replying { store.open(bundleID: record.bundleID) }
        }
        .onHover { hovering = $0 }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 8) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                heading
                    .lineLimit(1)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .lineLimit(replying ? 3 : 2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 6)
            if replying {
                EmptyView()
            } else if hovering {
                if quickReply {
                    Button {
                        reply.begin(record: record, vm: vm)
                    } label: {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.gray)
                    }
                    .buttonStyle(.plain)
                    .help("Reply")
                }
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
    }

    @ViewBuilder
    private var replyArea: some View {
        switch reply.phase {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .ready, .sending:
            HStack(spacing: 8) {
                TextField("Reply…", text: $reply.draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($focused)
                    .disabled(reply.phase == .sending)
                    .onSubmit { reply.send() }
                    .onExitCommand { reply.cancel() }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.1)))
                    .onChange(of: reply.focusToken) { _, _ in focused = true }
                    .onAppear { if reply.focusToken > 0 { focused = true } }
                if reply.phase == .sending {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 20, height: 20)
                } else {
                    Button { reply.send() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(reply.canSend ? Color.white : Color.gray)
                    }
                    .buttonStyle(.plain)
                    .disabled(!reply.canSend)
                    .frame(width: 20, height: 20)
                    Button { reply.cancel() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.gray)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 16, height: 20)
                    .help("Cancel")
                }
            }
        case .sent:
            Label("Sent", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)
        case .needsAccess:
            bar("Replying from the notch needs Accessibility.", "Allow…") { reply.requestAccess() }
        case .missing:
            bar("This notification is no longer in Notification Center.", "Open \(record.appName)") { reply.openApp() }
        case .note(let text):
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.gray)
                .lineLimit(2)
        }
    }

    private func bar(_ text: String, _ action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.gray)
                .lineLimit(1)
            Spacer(minLength: 6)
            Button(action, action: perform)
                .controlSize(.small)
            Button { reply.cancel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.gray)
            }
            .buttonStyle(.plain)
        }
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
