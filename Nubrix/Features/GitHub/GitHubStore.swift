import AppKit
import Defaults
import IOKit.ps
import Network
import SwiftUI

struct GitHubSessionRef: Equatable, Sendable {
    let repo: String
    let branch: String?
}

enum GitHubConnection: Equatable {
    case noToken
    case connecting
    case connected
    case unauthorized
    case rateLimited(Date)
    case failing(String)
}

@MainActor
final class GitHubStore: ObservableObject {
    static let shared = GitHubStore()
    static let idleInterval: TimeInterval = 120
    static let activeInterval: TimeInterval = 30
    static let quietInterval: TimeInterval = 450
    static let maxFailureDelay: TimeInterval = 900
    static let minimumGap: TimeInterval = 5
    static let repoListLifetime: TimeInterval = 600
    static let maxWatchedRepos = 10
    nonisolated static let maxDisplayedRuns = 12

    @Published private(set) var connection: GitHubConnection
    @Published private(set) var login: String
    @Published private(set) var myPRs: [GitHubPR] = []
    @Published private(set) var reviewRequests: [GitHubPR] = []
    @Published private(set) var runs: [GitHubRun] = []
    @Published private(set) var accessibleRepos: [GitHubRepoInfo] = []
    @Published private(set) var lastRefresh: Date?

    private let baseURL: URL
    private let client: GitHubClient
    private let tokens: GitHubTokenStoring
    private var sessionSource: () -> [GitHubSessionRef] = { [] }
    private var loop: Task<Void, Never>?
    private var snapshot: GitHubSnapshot?
    private var reposFetchedAt: Date?
    private var sectionVisible = false
    private var sleeping = false
    private var locked = false
    private var offline = false
    private var consecutiveFailures = 0
    private var pathMonitor: NWPathMonitor?
    private var started = false
    private var refreshing = false
    private var lastRefreshStart = Date.distantPast
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(baseURL: URL = URL(string: "https://api.github.com")!, tokens: GitHubTokenStoring = GitHubTokenStore()) {
        self.baseURL = baseURL
        self.tokens = tokens
        client = GitHubClient(baseURL: baseURL)
        connection = Defaults[.githubTokenSaved] ? .connecting : .noToken
        login = Defaults[.githubLogin]
    }

    var hasToken: Bool { connection != .noToken }
    var isPaused: Bool { sleeping || locked || offline }

    var hasRunInProgress: Bool { runs.contains { $0.state == .running } }

    func rateLimit() async -> GitHubRateLimit? { await client.rateLimit }

    func replace(connection: GitHubConnection? = nil, login: String? = nil, mine: [GitHubPR]? = nil,
                 reviews: [GitHubPR]? = nil, runs: [GitHubRun]? = nil, repos: [GitHubRepoInfo]? = nil) {
        if let connection, self.connection != connection { self.connection = connection }
        if let login, self.login != login { self.login = login }
        if let mine, myPRs != mine { myPRs = mine }
        if let reviews, reviewRequests != reviews { reviewRequests = reviews }
        if let runs, self.runs != runs { self.runs = runs }
        if let repos, accessibleRepos != repos { accessibleRepos = repos }
    }

    func pullRequest(repo: String?, branch: String?) -> GitHubPR? {
        guard let repo, let branch, !branch.isEmpty else { return nil }
        return myPRs.first { GitHubRemote.sameRepo($0.repo, repo) && $0.branch == branch }
    }

    func start(sessions: @escaping () -> [GitHubSessionRef]) {
        sessionSource = sessions
        guard !started else { return }
        started = true
        registerObservers()
        guard Defaults[.githubTokenSaved] else {
            connection = .noToken
            return
        }
        connection = .connecting
        let tokens = self.tokens
        Task {
            let token = await Task.detached { tokens.read() }.value
            guard let token else {
                Defaults[.githubTokenSaved] = false
                connection = .noToken
                return
            }
            await client.setToken(token)
            restartLoop()
        }
    }

    func connect(token raw: String) async -> String? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isFineGrainedToken(token) else {
            return "Paste a fine-grained token. It starts with github_pat_."
        }
        let probe = GitHubClient(baseURL: baseURL)
        await probe.setToken(token)
        let name: String
        do {
            name = try await probe.user()
        } catch let failure as GitHubFailure {
            return Self.message(for: failure)
        } catch {
            return "Could not reach GitHub."
        }
        let tokens = self.tokens
        let saved = await Task.detached { tokens.save(token) }.value
        guard saved else { return "Could not save the token to the Keychain." }
        await client.setToken(token)
        Defaults[.githubTokenSaved] = true
        Defaults[.githubLogin] = name
        snapshot = nil
        reposFetchedAt = nil
        replace(connection: .connecting, login: name)
        restartLoop()
        return nil
    }

    func disconnect() {
        loop?.cancel()
        loop = nil
        let tokens = self.tokens
        Task.detached { tokens.delete() }
        Task { await client.setToken(nil) }
        Defaults[.githubTokenSaved] = false
        Defaults[.githubLogin] = ""
        snapshot = nil
        reposFetchedAt = nil
        lastRefresh = nil
        replace(connection: .noToken, login: "", mine: [], reviews: [], runs: [], repos: [])
        GitHubNotifier.clearAll()
    }

    func setSectionVisible(_ visible: Bool) {
        guard visible != sectionVisible else { return }
        sectionVisible = visible
        if visible, hasToken { restartLoop() }
    }

    func refreshNow() {
        guard hasToken else { return }
        Task { await client.resetBackoff() }
        restartLoop(ignoringGap: true)
    }

    func setPaused(sleeping: Bool? = nil, locked: Bool? = nil, offline: Bool? = nil) {
        let before = isPaused
        if let sleeping { self.sleeping = sleeping }
        if let locked { self.locked = locked }
        if let offline { self.offline = offline }
        if isPaused {
            loop?.cancel()
            loop = nil
            if offline == true, hasToken, connection == .connected { replace(connection: .failing("Offline")) }
        } else if before, hasToken {
            consecutiveFailures = 0
            restartLoop()
        }
    }

    func setRepo(_ name: String, enabled: Bool) {
        var excluded = Defaults[.githubExcludedRepos].filter { !GitHubRemote.sameRepo($0, name) }
        if !enabled { excluded.append(name) }
        Defaults[.githubExcludedRepos] = excluded
        refreshNow()
    }

    func isRepoEnabled(_ name: String) -> Bool {
        !Defaults[.githubExcludedRepos].contains { GitHubRemote.sameRepo($0, name) }
    }

    @discardableResult
    func addRepo(_ text: String) -> Bool {
        guard let name = GitHubRemote.normalized(text) else { return false }
        var extras = Defaults[.githubExtraRepos]
        if !extras.contains(where: { GitHubRemote.sameRepo($0, name) }) { extras.append(name) }
        Defaults[.githubExtraRepos] = extras
        Defaults[.githubExcludedRepos] = Defaults[.githubExcludedRepos].filter { !GitHubRemote.sameRepo($0, name) }
        refreshNow()
        return true
    }

    func removeExtraRepo(_ name: String) {
        Defaults[.githubExtraRepos] = Defaults[.githubExtraRepos].filter { !GitHubRemote.sameRepo($0, name) }
        refreshNow()
    }

    static func isFineGrainedToken(_ token: String) -> Bool {
        guard token.hasPrefix("github_pat_"), token.count >= 30, token.count <= 255 else { return false }
        return token.unicodeScalars.allSatisfy { ($0.value >= 48 && $0.value <= 57) || ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) || $0 == "_" }
    }

    static func message(for failure: GitHubFailure) -> String {
        switch failure {
        case .unauthorized: return "GitHub rejected the token (expired, revoked or mistyped)."
        case .rateLimited: return "GitHub is rate limiting this token. Try again later."
        case .network: return "Could not reach GitHub."
        case .forbidden: return "The token is not allowed to read your profile."
        default: return "Unexpected response from GitHub."
        }
    }

    private func restartLoop(ignoringGap: Bool = false) {
        loop?.cancel()
        guard hasToken, !isPaused else { return }
        loop = Task { [weak self] in
            if !ignoringGap, let self {
                let wait = Self.minimumGap - Date().timeIntervalSince(self.lastRefreshStart)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait), tolerance: .seconds(1)) }
            }
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                if Task.isCancelled { return }
                if self.connection == .unauthorized { return }
                try? await Task.sleep(for: .seconds(self.nextDelay()), tolerance: .seconds(5))
            }
        }
    }

    private func nextDelay(now: Date = Date()) -> TimeInterval {
        var base = Self.idleInterval
        let runActive = hasRunInProgress
        if sectionVisible || (runActive && !Self.onBattery && !ProcessInfo.processInfo.isLowPowerModeEnabled) {
            base = Self.activeInterval
        } else if !sectionVisible, !runActive, sessionSource().isEmpty {
            base = Self.quietInterval
        }
        if case .rateLimited(let until) = connection { return max(base, until.timeIntervalSince(now) + 1) }
        if consecutiveFailures > 0 {
            let factor = pow(2, Double(min(consecutiveFailures, 10)))
            return max(base, min(base * factor, Self.maxFailureDelay))
        }
        return base
    }

    private static var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        return type == kIOPSBatteryPowerValue
    }

    private func refresh() async {
        guard hasToken, !refreshing, !isPaused else { return }
        if let until = await client.backoffUntil() {
            replace(connection: .rateLimited(until))
            return
        }
        refreshing = true
        defer { refreshing = false }
        lastRefreshStart = Date()
        do {
            var name = login
            if name.isEmpty {
                name = try await client.user()
                Defaults[.githubLogin] = name
                replace(login: name)
            }
            let found = try await client.pullRequests(login: name)
            var mine = found.mine
            if found.rollupUnavailable { mine = try await fillChecks(mine) }
            try await refreshRepoListIfNeeded()

            let excluded = Set(Defaults[.githubExcludedRepos].map { $0.lowercased() })
            mine = mine.filter { !excluded.contains($0.repo.lowercased()) }
            let review = found.reviewRequests.filter { !excluded.contains($0.repo.lowercased()) }

            let sessions = sessionSource()
            let watched = watchedRepos(mine: mine, review: review, sessions: sessions)
            let allRuns = try await fetchRuns(watched)

            let next = GitHubSnapshot(
                mine: mine.sorted { $0.updatedAt > $1.updatedAt },
                reviewRequests: review.sorted { $0.updatedAt > $1.updatedAt },
                runs: allRuns
            )
            var defaults: [String: String] = [:]
            for repo in accessibleRepos { defaults[repo.fullName.lowercased()] = repo.defaultBranch }
            var branches = Set<String>()
            for ref in sessions { if let branch = ref.branch { branches.insert(GitHubChangeDetector.branchKey(repo: ref.repo, branch: branch)) } }
            let context = GitHubDiffContext(login: name, defaultBranches: defaults, extraBranches: branches)
            let diff = GitHubChangeDetector.diff(previous: snapshot, current: next, context: context)
            snapshot = next
            consecutiveFailures = 0
            replace(connection: .connected, mine: next.mine, reviews: next.reviewRequests, runs: Self.displayRuns(next.runs))
            lastRefresh = Date()
            GitHubNotifier.deliver(diff)
        } catch let failure as GitHubFailure {
            switch failure {
            case .unauthorized: replace(connection: .unauthorized)
            case .rateLimited(let until): replace(connection: .rateLimited(until))
            case .network:
                consecutiveFailures += 1
                replace(connection: .failing("Offline"))
            default:
                consecutiveFailures += 1
                replace(connection: .failing("GitHub error"))
            }
        } catch {
            consecutiveFailures += 1
            replace(connection: .failing("GitHub error"))
        }
    }

    private func fillChecks(_ prs: [GitHubPR]) async throws -> [GitHubPR] {
        var result = prs
        var budget = 10
        for index in result.indices where result[index].checksUnavailable && budget > 0 {
            budget -= 1
            result[index].checks = try await client.checks(repo: result[index].repo, sha: result[index].headSHA)
            result[index].checksUnavailable = false
        }
        return result
    }

    private func refreshRepoListIfNeeded() async throws {
        if let fetched = reposFetchedAt, Date().timeIntervalSince(fetched) < Self.repoListLifetime { return }
        do {
            let repos = try await client.repos()
            reposFetchedAt = Date()
            replace(repos: repos)
        } catch let failure as GitHubFailure where failure == .unauthorized || failure.isRateLimit {
            throw failure
        } catch {
            reposFetchedAt = Date()
        }
    }

    private func watchedRepos(mine: [GitHubPR], review: [GitHubPR], sessions: [GitHubSessionRef]) -> [String] {
        let excluded = Set(Defaults[.githubExcludedRepos].map { $0.lowercased() })
        var ordered: [String] = []
        var seen = Set<String>()
        func add(_ name: String) {
            let key = name.lowercased()
            guard GitHubRemote.isValid(name), !excluded.contains(key), seen.insert(key).inserted else { return }
            ordered.append(name)
        }
        Defaults[.githubExtraRepos].forEach(add)
        sessions.forEach { add($0.repo) }
        mine.forEach { add($0.repo) }
        review.forEach { add($0.repo) }
        accessibleRepos.sorted { ($0.pushedAt ?? .distantPast) > ($1.pushedAt ?? .distantPast) }.forEach { add($0.fullName) }
        return Array(ordered.prefix(Self.maxWatchedRepos))
    }

    private func fetchRuns(_ repos: [String]) async throws -> [GitHubRun] {
        var all: [GitHubRun] = []
        for repo in repos {
            do {
                all += try await client.runs(repo: repo).runs
            } catch let failure as GitHubFailure {
                if failure == .unauthorized || failure.isRateLimit { throw failure }
            }
        }
        return all.sorted { $0.id > $1.id }
    }

    nonisolated static func displayRuns(_ all: [GitHubRun]) -> [GitHubRun] {
        var seen = Set<String>()
        var result: [GitHubRun] = []
        for run in all.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            let key = "\(run.repo.lowercased())|\(run.name)|\(run.branch)"
            guard seen.insert(key).inserted else { continue }
            result.append(run)
            if result.count >= maxDisplayedRuns { break }
        }
        return result
    }

    private func registerObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        func watch(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor @Sendable (GitHubStore) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in if let self { action(self) } }
            }
            observers.append((center, token))
        }
        watch(workspace, NSWorkspace.willSleepNotification) { $0.setPaused(sleeping: true) }
        watch(workspace, NSWorkspace.didWakeNotification) { $0.setPaused(sleeping: false) }
        watch(workspace, NSWorkspace.screensDidSleepNotification) { $0.setPaused(sleeping: true) }
        watch(workspace, NSWorkspace.screensDidWakeNotification) { $0.setPaused(sleeping: false) }
        watch(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.setPaused(locked: true) }
        watch(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.setPaused(locked: false) }
        watch(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.setPaused(locked: true) }
        watch(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.setPaused(locked: false) }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor in self?.setPaused(offline: offline) }
        }
        monitor.start(queue: DispatchQueue(label: "dev.nubrix.github.path", qos: .utility))
        pathMonitor = monitor
    }
}
