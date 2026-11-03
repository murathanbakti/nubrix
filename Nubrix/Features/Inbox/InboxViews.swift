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
    @EnvironmentObject var vm: NubrixViewModel
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

struct InboxSettings: View {
    @ObservedObject var inbox = NubrixInbox.shared
    @Default(.claudeEnabled) var claudeMaster
    @Default(.inboxClaudeEnabled) var claudeEnabled
    @Default(.inboxNotchctlEnabled) var notchctlEnabled
    @Default(.inboxGithubEnabled) var githubEnabled
    @Default(.devEnabled) var devMaster
    @Default(.githubEnabled) var githubMaster

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .inboxKeepIconInNotch) {
                    Text("Keep notification icon in the notch")
                }
            } footer: {
                SettingsFooter(
                    "Shows a small icon and count in the closed notch while something is unread.",
                    link: ("Learn more", SettingsLinks.notificationsGuide)
                )
            }

            Section {
                Defaults.Toggle(key: .inboxClaudeEnabled) {
                    Text("Claude Code")
                }
                .disabled(!claudeMaster)
                Defaults.Toggle(key: .inboxNotchctlEnabled) {
                    Text("notchctl")
                }
                .disabled(!devMaster)
                Defaults.Toggle(key: .inboxGithubEnabled) {
                    Text("GitHub")
                }
                .disabled(!githubMaster)
            } header: {
                Text("Sources")
            } footer: {
                SettingsFooter("Done, failed and needs-you events from Claude Code, notchctl and GitHub. Turning a source off clears its unread items.")
            }

            SystemNotificationSettingsSection()

            Section {
                HStack {
                    Text(inbox.unreadCount == 0 ? "Nothing unread" : "\(inbox.unreadCount) unread")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Mark all as read") { inbox.markAllRead() }
                        .disabled(inbox.unreadCount == 0)
                }
            } footer: {
                SettingsFooter("Items are marked read when you open their tab or click the notification. They are not kept after a restart.")
            }
        }
        .settingsPage(.notifications)
        .onChange(of: claudeEnabled) { _, on in
            if !on { inbox.markRead(.claude) }
        }
        .onChange(of: notchctlEnabled) { _, on in
            if !on { inbox.markRead(.notchctl) }
        }
        .onChange(of: githubEnabled) { _, on in
            if !on { inbox.markRead(.github) }
        }
    }
}
