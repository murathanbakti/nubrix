import AppKit
import Defaults
import Foundation

protocol ClaudePlanFetching: Sendable {
    func fetch() async -> ClaudePlanFetchResult
}

struct XPCClaudePlanFetcher: ClaudePlanFetching {
    func fetch() async -> ClaudePlanFetchResult {
        await withTaskGroup(of: ClaudePlanFetchResult.self) { group in
            group.addTask { await XPCHelperClient.shared.fetchClaudePlanUsage() }
            group.addTask {
                try? await Task.sleep(for: .seconds(ClaudePlanPolicy.requestTimeout))
                return .failure(.timeout)
            }
            let first = await group.next() ?? .failure(.failed)
            group.cancelAll()
            return first
        }
    }
}

@MainActor
final class ClaudePlanUsageStore: ObservableObject {
    static let shared = ClaudePlanUsageStore()

    @Published private(set) var snapshot: ClaudePlanSnapshot?
    @Published private(set) var failure: ClaudePlanFailure?

    private let fetcher: ClaudePlanFetching
    private let lastActivity: @MainActor () -> Date?
    private var fetchedAt: Date?
    private var lastAttempt: Date?
    private var lastStopRefresh: Date?
    private var failures = 0
    private var inFlight = false
    private var started = false
    private var sleeping = false
    private var locked = false
    private var loop: Task<Void, Never>?
    private var tracker: ClaudePlanAlertTracker
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(fetcher: ClaudePlanFetching = XPCClaudePlanFetcher(),
         lastActivity: @escaping @MainActor () -> Date? = {
             AgentSessionStore.shared.sessions.map(\.updatedAt).max()
         }) {
        self.fetcher = fetcher
        self.lastActivity = lastActivity
        tracker = ClaudePlanAlertTracker(fired: Set(Defaults[.claudePlanAlertKeys]))
    }

    deinit {
        for (center, token) in observers { center.removeObserver(token) }
    }

    var isEnabled: Bool { Defaults[.claudePlanUsageEnabled] }
    var isPaused: Bool { sleeping || locked }

    var current: ClaudePlanSnapshot? {
        guard isEnabled, let snapshot else { return nil }
        return ClaudePlanSnapshot(limits: snapshot.limits, fetchedAt: fetchedAt ?? snapshot.fetchedAt)
    }

    func start() {
        guard !started else { return }
        started = true
        restoreCache()
        registerObservers()
        restartLoop(initialDelay: 3)
    }

    func settingChanged() {
        if isEnabled {
            failures = 0
            restartLoop(initialDelay: 0)
        } else {
            loop?.cancel()
            loop = nil
            if snapshot != nil { snapshot = nil }
            if failure != nil { failure = nil }
            fetchedAt = nil
            Defaults[.claudePlanUsageCache] = nil
        }
    }

    func noteStop() {
        let now = Date()
        guard started, isEnabled, !isPaused,
              ClaudePlanPolicy.allowsStopRefresh(lastStopRefresh: lastStopRefresh, now: now) else { return }
        lastStopRefresh = now
        restartLoop(initialDelay: 2)
    }

    func notchOpened() {
        let now = Date()
        guard started, isEnabled, !isPaused else { return }
        let base = ClaudePlanPolicy.baseInterval(lastActivity: lastActivity(), now: now)
        guard ClaudePlanPolicy.shouldRefreshOnOpen(lastAttempt: lastAttempt, lastSuccess: fetchedAt,
                                                   failures: failures, base: base, now: now) else { return }
        restartLoop(initialDelay: 0)
    }

    func setPaused(sleeping: Bool? = nil, locked: Bool? = nil) {
        let before = isPaused
        if let sleeping { self.sleeping = sleeping }
        if let locked { self.locked = locked }
        if isPaused {
            loop?.cancel()
            loop = nil
        } else if before, started, isEnabled {
            restartLoop(initialDelay: 5)
        }
    }

    private func restartLoop(initialDelay: TimeInterval) {
        loop?.cancel()
        guard started, isEnabled, !isPaused else { return }
        loop = Task { [weak self] in
            if initialDelay > 0 { try? await Task.sleep(for: .seconds(initialDelay)) }
            while !Task.isCancelled {
                guard let self, self.isEnabled, !self.isPaused else { return }
                await self.refresh()
                if Task.isCancelled { return }
                try? await Task.sleep(for: .seconds(self.nextDelay(now: Date())))
            }
        }
    }

    private func nextDelay(now: Date) -> TimeInterval {
        let base = ClaudePlanPolicy.baseInterval(lastActivity: lastActivity(), now: now)
        return ClaudePlanPolicy.delay(base: base, failures: failures)
    }

    func refresh() async {
        guard !inFlight, isEnabled else { return }
        inFlight = true
        lastAttempt = Date()
        let result = await fetcher.fetch()
        inFlight = false
        guard isEnabled else { return }
        handle(result, now: Date())
    }

    func handle(_ result: ClaudePlanFetchResult, now: Date) {
        switch result {
        case .success(let fresh):
            failures = 0
            if failure != nil { failure = nil }
            fetchedAt = fresh.fetchedAt
            if snapshot?.limits != fresh.limits { snapshot = fresh }
            persist(fresh)
            deliver(tracker.newAlerts(for: fresh, now: now))
            Defaults[.claudePlanAlertKeys] = tracker.fired.sorted()
        case .failure(let reason):
            failures = min(failures + 1, 8)
            if failure != reason { failure = reason }
        }
    }

    private func deliver(_ alerts: [ClaudePlanAlert]) {
        for alert in alerts {
            NubrixInbox.shared.planUsage(alert)
            AgentSessionStore.shared.showPlanUsageBanner(alert)
        }
    }

    private func persist(_ snapshot: ClaudePlanSnapshot) {
        Defaults[.claudePlanUsageCache] = try? JSONEncoder().encode(snapshot)
    }

    private func restoreCache() {
        guard isEnabled, let data = Defaults[.claudePlanUsageCache], data.count <= ClaudePlanFetchResult.maxEnvelopeBytes,
              let cached = try? JSONDecoder().decode(ClaudePlanSnapshot.self, from: data) else { return }
        snapshot = cached
        fetchedAt = cached.fetchedAt
    }

    private func registerObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        func watch(_ center: NotificationCenter, _ name: Notification.Name,
                   _ action: @escaping @MainActor @Sendable (ClaudePlanUsageStore) -> Void) {
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
    }
}
