import Foundation

private final class GitHubNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum GitHubFailure: Error, Equatable {
    case noToken
    case unauthorized
    case forbidden
    case notFound
    case rateLimited(until: Date)
    case http(Int)
    case network
    case malformed

    var isRateLimit: Bool {
        if case .rateLimited = self { return true }
        return false
    }
}

struct GitHubRunsFetch: Equatable, Sendable {
    let runs: [GitHubRun]
    let notModified: Bool
}

actor GitHubClient {
    static let apiVersion = "2022-11-28"
    static let reserve = 25
    static let secondaryBackoff: TimeInterval = 60
    static let resources = ["core", "graphql"]

    private let base: URL
    private let session: URLSession
    private var token: String?
    private var runCache: [String: (etag: String, runs: [GitHubRun])] = [:]
    private var blockedUntil: Date?
    private var resourceBlocked: [String: Date] = [:]
    private var rateLimits: [String: GitHubRateLimit] = [:]
    private(set) var requestCount = 0
    private(set) var notModifiedCount = 0

    init(baseURL: URL = URL(string: "https://api.github.com")!, session: URLSession? = nil) {
        base = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 30
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            self.session = URLSession(configuration: configuration)
        }
    }

    var rateLimit: GitHubRateLimit? {
        rateLimits["core"] ?? rateLimits.values.min { $0.remaining < $1.remaining }
    }

    func setToken(_ value: String?) {
        token = value
        runCache.removeAll()
        blockedUntil = nil
        resourceBlocked.removeAll()
        rateLimits.removeAll()
    }

    var hasToken: Bool { token != nil }

    func resetBackoff() {
        blockedUntil = nil
        resourceBlocked.removeAll()
    }

    func backoffUntil(now: Date = Date()) -> Date? {
        if let blockedUntil, blockedUntil > now { return blockedUntil }
        let active = Self.resources.compactMap { resourceBlocked[$0] }.filter { $0 > now }
        if active.count == Self.resources.count { return active.min() }
        return nil
    }

    func user() async throws -> String {
        let (data, _) = try await send(path: "/user")
        do { return try GitHubParsing.login(from: data) } catch { throw GitHubFailure.malformed }
    }

    func repos(maxPages: Int = 3) async throws -> [GitHubRepoInfo] {
        var all: [GitHubRepoInfo] = []
        for page in 1...maxPages {
            let (data, response) = try await send(path: "/user/repos", query: [
                "per_page": "100", "page": String(page), "sort": "pushed",
                "affiliation": "owner,collaborator,organization_member",
            ])
            let batch: [GitHubRepoInfo]
            do { batch = try GitHubParsing.repos(from: data) } catch { throw GitHubFailure.malformed }
            all += batch
            let link = response.value(forHTTPHeaderField: "Link") ?? ""
            if !link.contains("rel=\"next\"") { break }
        }
        return all
    }

    func pullRequests(login: String) async throws -> GitHubPRSearchResult {
        let body: [String: Any] = [
            "query": GitHubParsing.pullRequestQuery,
            "variables": [
                "mine": "is:pr is:open archived:false author:\(login) sort:updated-desc",
                "review": "is:pr is:open archived:false review-requested:\(login) sort:updated-desc",
            ],
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await send(path: "/graphql", method: "POST", body: payload)
        do { return try GitHubParsing.pullRequests(from: data) } catch { throw GitHubFailure.malformed }
    }

    func runs(repo: String) async throws -> GitHubRunsFetch {
        guard GitHubRemote.isValid(repo) else { throw GitHubFailure.notFound }
        let cached = runCache[repo]
        let (data, response) = try await send(path: "/repos/\(repo)/actions/runs", query: ["per_page": "10"], etag: cached?.etag)
        if response.statusCode == 304, let cached {
            notModifiedCount += 1
            return GitHubRunsFetch(runs: cached.runs, notModified: true)
        }
        let runs: [GitHubRun]
        do { runs = try GitHubParsing.runs(from: data, repo: repo) } catch { throw GitHubFailure.malformed }
        if let etag = response.value(forHTTPHeaderField: "ETag") { runCache[repo] = (etag, runs) }
        return GitHubRunsFetch(runs: runs, notModified: false)
    }

    func checks(repo: String, sha: String) async throws -> GitHubCheckState {
        guard GitHubRemote.isValid(repo), sha.count >= 7, sha.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) }) else {
            return .none
        }
        var states: [GitHubCheckState] = []
        do {
            let (data, _) = try await send(path: "/repos/\(repo)/commits/\(sha)/status")
            states.append(GitHubParsing.combinedStatus(from: data))
        } catch let failure as GitHubFailure where failure == .unauthorized || failure.isRateLimit {
            throw failure
        } catch {}
        do {
            let (data, _) = try await send(path: "/repos/\(repo)/commits/\(sha)/check-runs", query: ["per_page": "50"])
            states.append(GitHubParsing.checkRuns(from: data))
        } catch let failure as GitHubFailure where failure == .unauthorized || failure.isRateLimit {
            throw failure
        } catch {}
        return GitHubCheckState.merged(states)
    }

    private func send(path: String, method: String = "GET", query: [String: String] = [:], body: Data? = nil,
                      etag: String? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let token else { throw GitHubFailure.noToken }
        let now = Date()
        let resource = path == "/graphql" ? "graphql" : "core"
        if let blockedUntil, blockedUntil > now { throw GitHubFailure.rateLimited(until: blockedUntil) }
        if let until = resourceBlocked[resource], until > now { throw GitHubFailure.rateLimited(until: until) }
        if let limit = rateLimits[resource], limit.remaining <= Self.reserve, limit.resetAt > now {
            resourceBlocked[resource] = limit.resetAt
            throw GitHubFailure.rateLimited(until: limit.resetAt)
        }
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw GitHubFailure.malformed }
        components.path = (components.path == "/" ? "" : components.path) + path
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw GitHubFailure.malformed }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Nubrix", forHTTPHeaderField: "User-Agent")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        requestCount += 1
        let data: Data
        let response: HTTPURLResponse
        do {
            let (d, r) = try await session.data(for: request, delegate: GitHubNoRedirect())
            guard let http = r as? HTTPURLResponse else { throw GitHubFailure.network }
            data = d
            response = http
        } catch let failure as GitHubFailure {
            throw failure
        } catch {
            throw GitHubFailure.network
        }
        updateRateLimit(response, fallback: resource)
        switch response.statusCode {
        case 200...299, 304:
            return (data, response)
        case 401:
            throw GitHubFailure.unauthorized
        case 403, 429:
            if let until = limitedUntil(response, data: data, resource: resource) {
                if rateLimits[resource].map({ $0.remaining == 0 && $0.resetAt == until }) == true {
                    resourceBlocked[resource] = until
                } else {
                    blockedUntil = until
                }
                throw GitHubFailure.rateLimited(until: until)
            }
            throw GitHubFailure.forbidden
        case 404:
            throw GitHubFailure.notFound
        default:
            throw GitHubFailure.http(response.statusCode)
        }
    }

    private func updateRateLimit(_ response: HTTPURLResponse, fallback: String) {
        guard let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap({ Int($0) }),
              let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap({ TimeInterval($0) })
        else { return }
        let resource = response.value(forHTTPHeaderField: "X-RateLimit-Resource")?.lowercased() ?? fallback
        rateLimits[resource] = GitHubRateLimit(remaining: remaining, resetAt: Date(timeIntervalSince1970: reset))
    }

    private func limitedUntil(_ response: HTTPURLResponse, data: Data, resource: String) -> Date? {
        let now = Date()
        if let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap({ TimeInterval($0) }) {
            return now.addingTimeInterval(max(1, min(retry, 3600)))
        }
        if let limit = rateLimits[resource], limit.remaining == 0, limit.resetAt > now { return limit.resetAt }
        let message = String(data: data.prefix(2000), encoding: .utf8)?.lowercased() ?? ""
        if message.contains("rate limit") { return now.addingTimeInterval(Self.secondaryBackoff) }
        return response.statusCode == 429 ? now.addingTimeInterval(Self.secondaryBackoff) : nil
    }
}
