import Foundation

struct GitHubPRSearchResult: Equatable, Sendable {
    var mine: [GitHubPR]
    var reviewRequests: [GitHubPR]
    var rollupUnavailable: Bool
}

enum GitHubParseError: Error, Equatable {
    case malformed
    case graphQL(String)
}

enum GitHubParsing {
    static let pullRequestQuery = """
    query($mine: String!, $review: String!) {
      mine: search(query: $mine, type: ISSUE, first: 30) { nodes { ...PR } }
      review: search(query: $review, type: ISSUE, first: 30) { nodes { ...PR } }
    }
    fragment PR on PullRequest {
      id number title url isDraft headRefName headRefOid updatedAt mergeable reviewDecision
      repository { nameWithOwner }
      author { login }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
    }
    """

    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return try? Date(text, strategy: .iso8601)
    }

    static func pullRequests(from data: Data) throws -> GitHubPRSearchResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GitHubParseError.malformed
        }
        let errors = root["errors"] as? [[String: Any]] ?? []
        guard let payload = root["data"] as? [String: Any] else {
            let message = errors.compactMap { $0["message"] as? String }.first ?? "No data"
            throw GitHubParseError.graphQL(message)
        }
        let rollupErrors = errors.contains { error in
            let path = (error["path"] as? [Any] ?? []).compactMap { $0 as? String }
            return path.contains("statusCheckRollup") || (error["type"] as? String) == "FORBIDDEN"
        }
        func list(_ key: String) -> [GitHubPR] {
            let nodes = ((payload[key] as? [String: Any])?["nodes"] as? [Any]) ?? []
            return nodes.compactMap { ($0 as? [String: Any]).flatMap { pullRequest($0, rollupErrors: rollupErrors) } }
        }
        let mine = list("mine")
        let review = list("review")
        let unavailable = (mine + review).contains { $0.checksUnavailable }
        return GitHubPRSearchResult(mine: mine, reviewRequests: review, rollupUnavailable: unavailable)
    }

    static func pullRequest(_ node: [String: Any], rollupErrors: Bool) -> GitHubPR? {
        guard let id = node["id"] as? String,
              let number = node["number"] as? Int,
              let title = node["title"] as? String,
              let urlText = node["url"] as? String, let url = URL(string: urlText), GitHubRemote.isGitHubURL(url),
              let repo = (node["repository"] as? [String: Any])?["nameWithOwner"] as? String,
              GitHubRemote.isValid(repo)
        else { return nil }
        let rollup = (((node["commits"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first?["commit"] as? [String: Any])?["statusCheckRollup"] as? [String: Any]
        var checks = GitHubCheckState.none
        var unavailable = false
        if let state = rollup?["state"] as? String {
            switch state {
            case "SUCCESS": checks = .success
            case "FAILURE", "ERROR": checks = .failure
            case "PENDING", "EXPECTED": checks = .pending
            default: checks = .none
            }
        } else if rollupErrors {
            unavailable = true
        }
        let review: GitHubReviewState
        switch node["reviewDecision"] as? String {
        case "APPROVED": review = .approved
        case "CHANGES_REQUESTED": review = .changesRequested
        case "REVIEW_REQUIRED": review = .reviewRequired
        default: review = .none
        }
        let merge: GitHubMergeState
        switch node["mergeable"] as? String {
        case "MERGEABLE": merge = .mergeable
        case "CONFLICTING": merge = .conflicting
        default: merge = .unknown
        }
        return GitHubPR(
            id: id,
            repo: repo,
            number: number,
            title: title,
            url: url,
            branch: node["headRefName"] as? String ?? "",
            headSHA: node["headRefOid"] as? String ?? "",
            author: (node["author"] as? [String: Any])?["login"] as? String ?? "",
            isDraft: node["isDraft"] as? Bool ?? false,
            checks: checks,
            review: review,
            merge: merge,
            updatedAt: date(node["updatedAt"]) ?? Date(timeIntervalSince1970: 0),
            checksUnavailable: unavailable
        )
    }

    static func runs(from data: Data, repo: String) throws -> [GitHubRun] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["workflow_runs"] as? [[String: Any]]
        else { throw GitHubParseError.malformed }
        return items.compactMap { item in
            guard let id = item["id"] as? Int,
                  let status = item["status"] as? String,
                  let urlText = item["html_url"] as? String, let url = URL(string: urlText), GitHubRemote.isGitHubURL(url)
            else { return nil }
            let name = item["name"] as? String ?? "Workflow"
            return GitHubRun(
                id: id,
                repo: repo,
                name: name,
                title: item["display_title"] as? String ?? name,
                branch: item["head_branch"] as? String ?? "",
                event: item["event"] as? String ?? "",
                status: status,
                conclusion: item["conclusion"] as? String,
                url: url,
                actor: (item["actor"] as? [String: Any])?["login"] as? String ?? "",
                createdAt: date(item["created_at"]) ?? Date(timeIntervalSince1970: 0),
                updatedAt: date(item["updated_at"]) ?? Date(timeIntervalSince1970: 0)
            )
        }
    }

    static func repos(from data: Data) throws -> [GitHubRepoInfo] {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw GitHubParseError.malformed
        }
        return items.compactMap { item in
            guard let name = item["full_name"] as? String, GitHubRemote.isValid(name) else { return nil }
            if item["archived"] as? Bool == true || item["disabled"] as? Bool == true { return nil }
            return GitHubRepoInfo(fullName: name, defaultBranch: item["default_branch"] as? String ?? "main", pushedAt: date(item["pushed_at"]))
        }
    }

    static func login(from data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = root["login"] as? String, !login.isEmpty,
              login.unicodeScalars.allSatisfy({ ($0.value >= 48 && $0.value <= 57) || ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) || $0 == "-" || $0 == "_" })
        else { throw GitHubParseError.malformed }
        return login
    }

    static func combinedStatus(from data: Data) -> GitHubCheckState {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["total_count"] as? Int ?? 0) > 0
        else { return .none }
        switch root["state"] as? String {
        case "success": return .success
        case "failure", "error": return .failure
        case "pending": return .pending
        default: return .none
        }
    }

    static func checkRuns(from data: Data) -> GitHubCheckState {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runs = root["check_runs"] as? [[String: Any]], !runs.isEmpty
        else { return .none }
        var states: [GitHubCheckState] = []
        for run in runs {
            if run["status"] as? String != "completed" { states.append(.pending); continue }
            switch run["conclusion"] as? String ?? "" {
            case "failure", "timed_out", "cancelled", "action_required", "startup_failure": states.append(.failure)
            case "success", "neutral", "skipped": states.append(.success)
            default: states.append(.none)
            }
        }
        return GitHubCheckState.merged(states)
    }
}
