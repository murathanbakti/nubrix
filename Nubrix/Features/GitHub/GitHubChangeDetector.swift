import Foundation

struct GitHubSnapshot: Equatable, Sendable {
    var mine: [GitHubPR] = []
    var reviewRequests: [GitHubPR] = []
    var runs: [GitHubRun] = []
}

struct GitHubDiffContext: Sendable {
    var login: String
    var defaultBranches: [String: String]
    var extraBranches: Set<String>
    var now: Date = Date()
    var maxRunAge: TimeInterval = 30 * 60
}

enum GitHubEventKind: Equatable, Sendable {
    case reviewRequested
    case ciFailed
    case ciPassed
    case conflict
    case runFailed
}

struct GitHubEvent: Equatable, Sendable {
    let kind: GitHubEventKind
    let key: String
    let title: String
    let message: String
    let url: URL
}

struct GitHubDiff: Equatable, Sendable {
    var events: [GitHubEvent] = []
    var resolved: [String] = []
}

enum GitHubChangeDetector {
    static func branchKey(repo: String, branch: String) -> String {
        "\(repo.lowercased())#\(branch)"
    }

    static func diff(previous: GitHubSnapshot?, current: GitHubSnapshot, context: GitHubDiffContext) -> GitHubDiff {
        guard let previous else { return GitHubDiff() }
        var result = GitHubDiff()
        let oldMine = Dictionary(previous.mine.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let oldReview = Set(previous.reviewRequests.map(\.id))
        let oldRuns = Dictionary(previous.runs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for pr in current.reviewRequests where !oldReview.contains(pr.id) {
            result.events.append(GitHubEvent(
                kind: .reviewRequested, key: "review:\(pr.id)", title: pr.repo,
                message: "Review requested #\(pr.number)", url: pr.url
            ))
        }
        let reviewIDs = Set(current.reviewRequests.map(\.id))
        for id in oldReview where !reviewIDs.contains(id) { result.resolved.append("review:\(id)") }

        for pr in current.mine {
            let old = oldMine[pr.id]
            if pr.checks == .failure, old?.checks != .failure, !pr.checksUnavailable {
                result.events.append(GitHubEvent(kind: .ciFailed, key: "ci:\(pr.id)", title: pr.repo, message: "CI failed #\(pr.number)", url: pr.url))
            } else if pr.checks == .success, old?.checks == .pending {
                result.events.append(GitHubEvent(kind: .ciPassed, key: "ci:\(pr.id)", title: pr.repo, message: "CI passed #\(pr.number)", url: pr.url))
            }
            if pr.checks != .failure, old?.checks == .failure { result.resolved.append("ci:\(pr.id)") }
            if pr.merge == .conflicting, old?.merge != .conflicting {
                result.events.append(GitHubEvent(kind: .conflict, key: "conflict:\(pr.id)", title: pr.repo, message: "Conflicts #\(pr.number)", url: pr.url))
            }
            if pr.merge != .conflicting, old?.merge == .conflicting { result.resolved.append("conflict:\(pr.id)") }
        }
        let currentMine = Set(current.mine.map(\.id))
        for id in oldMine.keys where !currentMine.contains(id) {
            result.resolved.append("ci:\(id)")
            result.resolved.append("conflict:\(id)")
        }

        var myBranches = context.extraBranches
        for pr in current.mine { myBranches.insert(branchKey(repo: pr.repo, branch: pr.branch)) }
        let cutoff = context.now.addingTimeInterval(-context.maxRunAge)
        for run in current.runs where run.state == .failure {
            if oldRuns[run.id]?.state == .failure { continue }
            if run.updatedAt < cutoff { continue }
            let defaultBranch = context.defaultBranches[run.repo.lowercased()]
            let onDefault = defaultBranch.map { $0 == run.branch } ?? (run.branch == "main" || run.branch == "master")
            let onMine = myBranches.contains(branchKey(repo: run.repo, branch: run.branch))
            let byMe = !context.login.isEmpty && run.actor.caseInsensitiveCompare(context.login) == .orderedSame
            guard onDefault || onMine || byMe else { continue }
            result.events.append(GitHubEvent(
                kind: .runFailed, key: "run:\(run.id)", title: run.repo,
                message: "\(run.name) failed on \(run.branch)", url: run.url
            ))
        }
        return result
    }
}
