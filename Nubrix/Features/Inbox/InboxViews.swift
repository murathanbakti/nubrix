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
    @Default(.claudePlanUsageEnabled) var planUsageEnabled
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
                Text("While something is unread, the closed notch keeps a small icon and count. When this is off, or when music is playing, the closed notch shows nothing; unread items are marked with a dot on their tab once you open the notch.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
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
                Text("Done, failed and needs-you events from Claude Code sessions, and notifications sent with notchctl. Notifications from other apps are set up under Other apps below. Turning a source off also clears its unread items.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            SystemNotificationSettingsSection()

            Section {
                Defaults.Toggle(key: .claudeEnabled) {
                    Text("Claude Code integration")
                }
                Group {
                    Defaults.Toggle(key: .claudeNotchApprovals) {
                        Text("Approve Claude Code permissions from the notch")
                    }
                    Defaults.Toggle(key: .claudeOpenSession) {
                        Text("Open the session when you click it (Terminal, iTerm and Ghostty need Automation)")
                    }
                    Defaults.Toggle(key: .homeShowClaudeUsage) {
                        Text("Show 5-hour and weekly usage on the Home tab")
                    }
                    Defaults.Toggle(key: .claudePlanUsageEnabled) {
                        Text("Show official plan usage (runs `claude /usage` in the background)")
                    }
                }
                .disabled(!claudeMaster)
            } header: {
                Text("Claude Code")
            } footer: {
                Text("When Claude Code asks for permission, the notch shows the command with Allow and Deny. Nothing is ever approved automatically; if Nubrix is not running or you do not answer in time, Claude Code asks in its own window as usual. Requires the nubrix-permission hook. The Home tab card shows your official session and weekly usage from Claude. Plan usage is read by running `claude /usage` with the installed Claude Code CLI every 5 to 30 minutes; it costs no tokens, loads no hooks or project settings, and only the percentages and reset times are kept. Without it, the card falls back to the status line limits or an estimate from your Claude Code transcripts. It is hidden while a meeting countdown is showing. When the integration is off, Nubrix stops listening for Claude Code hooks (notchctl keeps working while the Dev tab is on) and the hooks do nothing.")
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
                Text("Items are marked read when you open the Claude, Dev or Notifications tab, or click the notification. They are not kept after a restart.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            MeetingSettingsSection()
        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
        .onChange(of: planUsageEnabled) { _, _ in ClaudePlanUsageStore.shared.settingChanged() }
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
