import Defaults
import SwiftUI

extension InboxSource {
    var targetTab: NotchViews {
        switch self {
        case .claude: return .agents
        case .notchctl, .github: return .dev
        case .system: return .notifications
        }
    }

    var title: String {
        switch self {
        case .claude: return "Claude Code"
        case .notchctl: return "notchctl"
        case .github: return "GitHub"
        case .system: return "Notifications"
        }
    }

    var isEnabled: Bool {
        switch self {
        case .claude: return Defaults[.inboxClaudeEnabled]
        case .notchctl: return Defaults[.inboxNotchctlEnabled]
        case .github: return Defaults[.inboxGithubEnabled]
        case .system: return Defaults[.systemNotificationsEnabled]
        }
    }

    static func sources(for tab: NotchViews) -> [InboxSource] {
        switch tab {
        case .agents: return [.claude]
        case .dev: return [.notchctl, .github]
        case .notifications: return [.system]
        case .home: return []
        default: return []
        }
    }
}

@MainActor
final class NubrixInbox: ObservableObject {
    static let shared = NubrixInbox()

    @Published private(set) var ledger = InboxLedger()

    private init() {}

    private func update(_ change: (inout InboxLedger) -> Bool) {
        var copy = ledger
        if change(&copy) { ledger = copy }
    }

    var entries: [InboxEntry] { ledger.entries }
    var unreadCount: Int { ledger.unreadCount }
    var topSeverity: InboxSeverity? { ledger.topSeverity }
    var newest: InboxEntry? { ledger.newest }

    var showsWing: Bool { Defaults[.inboxKeepIconInNotch] && ledger.unreadCount > 0 }

    func severity(for tab: NotchViews) -> InboxSeverity? {
        InboxSource.sources(for: tab).compactMap { ledger.topSeverity(for: $0) }.max()
    }

    func sessionChanged(id: String, project: String, state: AgentSessionState, detail: String?) {
        guard InboxSource.claude.isEnabled else { return }
        switch state {
        case .working:
            update { $0.clearNeedsYou(session: id) }
        case .needsAttention:
            update { $0.recordSession(id: id, severity: .needsYou, title: project, message: detail ?? state.title) }
        case .failed:
            update { $0.recordSession(id: id, severity: .failed, title: project, message: detail ?? state.title) }
        case .done:
            update { $0.recordSession(id: id, severity: .done, title: project, message: detail ?? state.title) }
        case .idle:
            break
        }
    }

    func sessionEnded(id: String) {
        update { $0.clearNeedsYou(session: id) }
        update { $0.clearSession(id) }
    }

    func contextWarning(id: String, project: String, percent: Double) {
        guard InboxSource.claude.isEnabled else { return }
        update { $0.recordContextWarning(id: id, title: project, message: "Context \(Int(percent.rounded()))% — consider /compact") }
    }

    func planUsage(_ alert: ClaudePlanAlert) {
        guard InboxSource.claude.isEnabled else { return }
        let locale = Locale.current
        let name = alert.isSession ? ClaudeUsageText.session(locale) : ClaudeUsageText.week(locale)
        let percent = ClaudeUsageText.percent(alert.percent)
        let reset = ClaudeUsageText.resets(alert.resetsAt, now: Date(), locale: locale)
        let tr = ClaudeUsageText.isTurkish(locale)
        let message = tr ? "\(name) limitinin \(percent) kısmı kullanıldı · \(reset)" : "\(name) limit \(percent) used · \(reset)"
        update {
            $0.recordPlanUsage(key: "plan|\(alert.kind)|\(alert.threshold)|\(Int(alert.resetsAt.timeIntervalSince1970))",
                               severity: alert.threshold >= 95 ? .failed : .notice,
                               title: "Claude", message: message)
        }
    }

    func notchctl(title: String?, message: String) {
        guard InboxSource.notchctl.isEnabled else { return }
        update { $0.recordNotice(title: title ?? "notchctl", message: message) }
    }

    func system(title: String, message: String) {
        guard InboxSource.system.isEnabled else { return }
        update { $0.recordSystem(title: title, message: message) }
    }

    func github(_ event: GitHubEvent) {
        guard InboxSource.github.isEnabled else { return }
        let severity: InboxSeverity
        switch event.kind {
        case .reviewRequested: severity = .notice
        case .ciPassed: severity = .done
        case .ciFailed, .runFailed, .conflict: severity = .failed
        }
        update { $0.recordGitHub(key: event.key, severity: severity, title: event.title, message: event.message) }
    }

    func githubResolved(_ keys: [String]) {
        update { $0.clearGitHub(keys: keys) }
    }

    func markViewed(_ tab: NotchViews) {
        for source in InboxSource.sources(for: tab) where ledger.unreadCount(for: source) > 0 {
            update { $0.markRead(source: source) }
        }
    }

    func markRead(_ source: InboxSource) {
        guard ledger.unreadCount(for: source) > 0 else { return }
        update { $0.markRead(source: source) }
    }

    func markAllRead() {
        guard ledger.unreadCount > 0 else { return }
        update { $0.markAllRead() }
    }
}
