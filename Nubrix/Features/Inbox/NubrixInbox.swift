import Defaults
import SwiftUI

extension InboxSource {
    var targetTab: NotchViews {
        switch self {
        case .claude: return .agents
        case .notchctl: return .dev
        }
    }

    var title: String {
        switch self {
        case .claude: return "Claude Code"
        case .notchctl: return "notchctl"
        }
    }

    var isEnabled: Bool {
        switch self {
        case .claude: return Defaults[.inboxClaudeEnabled]
        case .notchctl: return Defaults[.inboxNotchctlEnabled]
        }
    }

    init?(tab: NotchViews) {
        switch tab {
        case .agents: self = .claude
        case .dev: self = .notchctl
        default: return nil
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
        InboxSource(tab: tab).flatMap { ledger.topSeverity(for: $0) }
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

    func notchctl(title: String?, message: String) {
        guard InboxSource.notchctl.isEnabled else { return }
        update { $0.recordNotice(title: title ?? "notchctl", message: message) }
    }

    func markViewed(_ tab: NotchViews) {
        guard let source = InboxSource(tab: tab), ledger.unreadCount(for: source) > 0 else { return }
        update { $0.markRead(source: source) }
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
