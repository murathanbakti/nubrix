import Defaults
import Foundation

@MainActor
enum GitHubNotifier {
    static func deliver(_ diff: GitHubDiff) {
        if !diff.resolved.isEmpty { NubrixInbox.shared.githubResolved(diff.resolved) }
        var banner: GitHubEvent?
        for event in diff.events where isEnabled(event.kind) {
            NubrixInbox.shared.github(event)
            if banner == nil || priority(event.kind) > priority(banner!.kind) { banner = event }
        }
        if let banner {
            DevNotificationStore.shared.showGitHub(title: banner.title, message: banner.message, style: style(banner.kind))
        }
    }

    static func clearAll() {
        NubrixInbox.shared.markRead(.github)
    }

    static func isEnabled(_ kind: GitHubEventKind) -> Bool {
        switch kind {
        case .reviewRequested: return Defaults[.githubNotifyReviews]
        case .ciFailed, .ciPassed, .runFailed: return Defaults[.githubNotifyCI]
        case .conflict: return Defaults[.githubNotifyConflicts]
        }
    }

    static func priority(_ kind: GitHubEventKind) -> Int {
        switch kind {
        case .ciFailed, .runFailed: return 3
        case .conflict, .reviewRequested: return 2
        case .ciPassed: return 1
        }
    }

    static func style(_ kind: GitHubEventKind) -> DevNotificationStyle {
        switch kind {
        case .ciFailed, .runFailed: return .error
        case .conflict: return .warning
        case .reviewRequested: return .info
        case .ciPassed: return .success
        }
    }
}
