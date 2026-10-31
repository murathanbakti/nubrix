import Foundation

enum GitHubCheckState: String, Equatable, Sendable {
    case success, failure, pending, none

    static func merged(_ states: [GitHubCheckState]) -> GitHubCheckState {
        if states.contains(.failure) { return .failure }
        if states.contains(.pending) { return .pending }
        if states.contains(.success) { return .success }
        return .none
    }
}

enum GitHubReviewState: String, Equatable, Sendable {
    case approved, changesRequested, reviewRequired, none
}

enum GitHubMergeState: String, Equatable, Sendable {
    case mergeable, conflicting, unknown
}

struct GitHubPR: Identifiable, Equatable, Sendable {
    let id: String
    let repo: String
    let number: Int
    let title: String
    let url: URL
    let branch: String
    let headSHA: String
    let author: String
    var isDraft: Bool
    var checks: GitHubCheckState
    var review: GitHubReviewState
    var merge: GitHubMergeState
    let updatedAt: Date
    var checksUnavailable = false

    var reference: String { "\(repo)#\(number)" }
}

enum GitHubRunState: String, Equatable, Sendable {
    case running, success, failure, cancelled, neutral
}

struct GitHubRun: Identifiable, Equatable, Sendable {
    let id: Int
    let repo: String
    let name: String
    let title: String
    let branch: String
    let event: String
    let status: String
    let conclusion: String?
    let url: URL
    let actor: String
    let createdAt: Date
    let updatedAt: Date

    var state: GitHubRunState {
        guard status == "completed" else { return .running }
        switch conclusion ?? "" {
        case "success": return .success
        case "failure", "timed_out", "startup_failure": return .failure
        case "cancelled": return .cancelled
        default: return .neutral
        }
    }
}

struct GitHubRepoInfo: Identifiable, Equatable, Sendable {
    let fullName: String
    let defaultBranch: String
    let pushedAt: Date?
    var id: String { fullName }
}

struct GitHubRateLimit: Equatable, Sendable {
    var remaining: Int
    var resetAt: Date
}

enum GitHubRemote {
    static func isValid(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let owner = parts[0], repo = parts[1]
        guard (1...39).contains(owner.count), (1...100).contains(repo.count) else { return false }
        guard repo != ".", repo != ".." else { return false }
        guard let first = owner.unicodeScalars.first, isAlnum(first) else { return false }
        guard owner.unicodeScalars.allSatisfy({ isAlnum($0) || $0 == "-" }) else { return false }
        return repo.unicodeScalars.allSatisfy { isAlnum($0) || $0 == "-" || $0 == "_" || $0 == "." }
    }

    static func normalized(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.hasSuffix(".git") { value.removeLast(4) }
        return isValid(value) ? value : nil
    }

    static func sameRepo(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    static func isGitHubURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == "github.com" && url.user == nil && url.port == nil
    }

    private static func isAlnum(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.value >= 48 && scalar.value <= 57) || (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 97 && scalar.value <= 122)
    }
}
