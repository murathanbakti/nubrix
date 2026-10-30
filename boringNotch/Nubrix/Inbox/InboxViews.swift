import Defaults
import SwiftUI

extension InboxSeverity {
    var tint: Color {
        switch self {
        case .needsYou: return .orange
        case .failed: return .red
        case .done: return .green
        case .notice: return Color(red: 0.35, green: 0.65, blue: 1.0)
        }
    }

    var symbol: String {
        switch self {
        case .needsYou: return "exclamationmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .done: return "checkmark.circle.fill"
        case .notice: return "bell.fill"
        }
    }
}

struct InboxGlyph: View {
    let severity: InboxSeverity
    var size: CGFloat = 14

    var body: some View {
        Group {
            switch severity {
            case .needsYou:
                AgentStatusGlyph(state: .needsAttention, size: size)
            case .failed:
                AgentStatusGlyph(state: .failed, size: size)
            case .done:
                AgentStatusGlyph(state: .done, size: size)
            case .notice:
                Image(systemName: severity.symbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(severity.tint)
                    .frame(width: size, height: size)
            }
        }
    }
}

struct InboxLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var inbox = NubrixInbox.shared

    var body: some View {
        let side = max(0, vm.effectiveClosedNotchHeight - 12)
        let severity = inbox.topSeverity ?? .notice
        HStack {
            InboxGlyph(severity: severity, size: side * 0.8)
                .frame(width: side, height: side)
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)
            Text("\(inbox.unreadCount)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(severity.tint)
                .frame(width: side, height: side)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

struct InboxBadgeDot: View {
    let severity: InboxSeverity

    var body: some View {
        Circle()
            .fill(severity.tint)
            .frame(width: 6, height: 6)
            .background(Circle().fill(.black).padding(-1))
    }
}

struct InboxEdgeDot: View {
    @EnvironmentObject var vm: BoringViewModel
    let severity: InboxSeverity

    var body: some View {
        InboxBadgeDot(severity: severity)
            .offset(x: 9, y: max(0, (vm.effectiveClosedNotchHeight - 6) / 2))
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

struct InboxSettings: View {
    @ObservedObject var inbox = NubrixInbox.shared
    @Default(.inboxClaudeEnabled) var claudeEnabled
    @Default(.inboxNotchctlEnabled) var notchctlEnabled

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .inboxKeepIconInNotch) {
                    Text("Keep notification icon in the notch")
                }
            } footer: {
                Text("While something is unread, the closed notch keeps a small icon and count. When this is off, or when music is playing, a small dot beside the notch is shown instead. Tabs with unread items always show a dot.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Defaults.Toggle(key: .inboxClaudeEnabled) {
                    Text("Claude Code")
                }
                Defaults.Toggle(key: .inboxNotchctlEnabled) {
                    Text("notchctl")
                }
            } header: {
                Text("Sources")
            } footer: {
                Text("Done, failed and needs-you events from Claude Code sessions, and notifications sent with notchctl. Other apps' notifications cannot be read. Turning a source off also clears its unread items.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                HStack {
                    Text(inbox.unreadCount == 0 ? "Nothing unread" : "\(inbox.unreadCount) unread")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Mark all as read") { inbox.markAllRead() }
                        .disabled(inbox.unreadCount == 0)
                }
            } footer: {
                Text("Items are marked read when you open the Claude or Dev tab, or click the notification. They are not kept after a restart.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
        .onChange(of: claudeEnabled) { _, on in
            if !on { inbox.markRead(.claude) }
        }
        .onChange(of: notchctlEnabled) { _, on in
            if !on { inbox.markRead(.notchctl) }
        }
    }
}
