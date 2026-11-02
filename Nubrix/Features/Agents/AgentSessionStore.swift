import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

@MainActor
final class AgentActivity: ObservableObject {
    static let shared = AgentActivity()

    @Published private(set) var banner: AgentBanner?
    @Published private(set) var needsAttention = false
    @Published private(set) var isWorking = false
    @Published private(set) var activeCount = 0

    func update(banner: AgentBanner?, sessions: [AgentSession]) {
        if self.banner != banner { self.banner = banner }
        let attention = sessions.contains { $0.state == .needsAttention }
        let working = sessions.contains { $0.state == .working }
        let count = sessions.filter { $0.state == .working || $0.state == .needsAttention }.count
        if needsAttention != attention { needsAttention = attention }
        if isWorking != working { isWorking = working }
        if activeCount != count { activeCount = count }
    }
}

@MainActor
final class AgentSessionStore: ObservableObject {
    static let shared = AgentSessionStore()

    @Published private(set) var sessions: [AgentSession] = [] {
        didSet { publishActivity() }
    }
    @Published private(set) var banner: AgentBanner? {
        didSet { publishActivity() }
    }
    @Published private(set) var rateLimits: AgentRateLimits?
    @Published private(set) var today: AgentDailyUsage
    @Published private(set) var ledger: ClaudeUsageLedger {
        didSet { ledgerVersion &+= 1 }
    }

    static let contextWarningThreshold = 85.0
    static let contextRearmThreshold = 70.0
    private(set) var lastHookEventAt: Date?
    private(set) var lastStatusAt: Date?
    private(set) var lastPermissionRequestAt: Date?
    var serverPort: UInt16?
    private(set) var rateLimitsUpdatedAt = Date.distantPast
    private var statusSeen: [String: Date] = [:]
    static let statusFreshness: TimeInterval = 120

    private var bannerTask: Task<Void, Never>?
    private var sweepTask: Task<Void, Never>?
    private let retention: TimeInterval = 12 * 60 * 60

    private let ledgerURL: URL
    private let ledgerQueue = DispatchQueue(label: "nubrix.claude-usage-ledger", qos: .utility)
    private var ledgerSaveTask: Task<Void, Never>?
    private var ledgerLoaded = false
    private var ledgerDirty = false
    private var ledgerVersion = 0
    private var summaryCache: (key: SummaryCacheKey, value: ClaudeUsageSummary?)?
    private var terminationObserver: NSObjectProtocol?
    private var enabledCancellable: AnyCancellable?

    private convenience init() {
        self.init(ledgerURL: ClaudeUsageLedgerFile.defaultURL)
    }

    init(ledgerURL: URL) {
        self.ledgerURL = ledgerURL
        let empty = ClaudeUsageLedger()
        ledger = empty
        today = empty.today(now: Date())
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushLedger(wait: true) }
        }
        if Defaults[.claudeEnabled] { startSweep() }
        enabledCancellable = Defaults.publisher(.claudeEnabled, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self else { return }
                if change.newValue { self.activate() } else { self.deactivate() }
            }
        loadLedger()
    }

    private func loadLedger() {
        let url = ledgerURL
        ledgerQueue.async { [weak self] in
            let existed = FileManager.default.fileExists(atPath: url.path)
            let loaded = ClaudeUsageLedgerFile.load(from: url, now: Date())
            Task { @MainActor in self?.finishLoadingLedger(loaded, fileExisted: existed) }
        }
    }

    private func finishLoadingLedger(_ file: ClaudeUsageLedger, fileExisted: Bool) {
        let now = Date()
        var merged = ClaudeUsageLedger(records: file.records + ledger.records, now: now)
        var migrated = false
        if !fileExisted {
            let stored = AgentDailyUsage(stored: Defaults[.claudeDailyUsage], now: now)
            if let record = ClaudeUsageLedger.migratedRecord(daily: stored) {
                merged.append(record, now: now)
                migrated = true
            }
        }
        ledgerLoaded = true
        ledger = merged
        refreshToday(now: now)
        if migrated {
            Defaults[.claudeDailyUsage] = [:]
            flushLedger(wait: false)
        } else if ledgerDirty {
            scheduleLedgerSave()
        }
        ledgerDirty = false
    }

    private func publishActivity() {
        AgentActivity.shared.update(banner: banner, sessions: sessions)
    }

    private func startSweep() {
        guard sweepTask == nil else { return }
        sweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60), tolerance: .seconds(30))
                self?.sweep()
            }
        }
    }

    func activate() {
        startSweep()
    }

    func deactivate() {
        sweepTask?.cancel()
        sweepTask = nil
        bannerTask?.cancel()
        bannerTask = nil
        flushLedger(wait: false)
        AgentPermissionStore.shared.withdrawAll()
        sessions = []
        statusSeen = [:]
        rateLimits = nil
        rateLimitsUpdatedAt = .distantPast
        lastHookEventAt = nil
        lastStatusAt = nil
        lastPermissionRequestAt = nil
        banner = nil
        NubrixInbox.shared.markRead(.claude)
    }

    var sortedSessions: [AgentSession] {
        sessions.sorted { lhs, rhs in
            lhs.state == rhs.state ? lhs.updatedAt > rhs.updatedAt : lhs.state < rhs.state
        }
    }

    var activeCount: Int { sessions.filter { $0.state == .working || $0.state == .needsAttention }.count }
    var needsAttention: Bool { sessions.contains { $0.state == .needsAttention } }
    var isWorking: Bool { sessions.contains { $0.state == .working } }

    func notePermissionRequest() {
        lastPermissionRequestAt = Date()
    }

    func apply(_ event: AgentHookEvent) {
        guard Defaults[.claudeEnabled] else { return }
        let now = Date()
        lastHookEventAt = now
        if Defaults[.claudeLastActivity].map({ now.timeIntervalSince($0) >= 60 }) ?? true {
            Defaults[.claudeLastActivity] = now
        }
        if event.name == "Stop" { ClaudePlanUsageStore.shared.noteStop() }
        if event.name == "SessionStart" || event.name == "UserPromptSubmit" { ClaudePlanUsageStore.shared.noteActivity() }
        if event.name == "SessionEnd" {
            sessions.removeAll { $0.id == event.sessionID }
            NubrixInbox.shared.sessionEnded(id: event.sessionID)
            if banner?.sessionID == event.sessionID { dismissBanner() }
            return
        }

        let index = sessions.firstIndex { $0.id == event.sessionID }
        if event.name == "SubagentStop" {
            if let index, let usage = event.usage {
                var session = sessions[index]
                absorb(usage, into: &session, accumulate: false, now: now)
                if session != sessions[index] { sessions[index] = session }
            }
            return
        }
        let current = index.map { sessions[$0].state }
        guard let next = Self.state(after: event, current: current) else { return }

        var session = index.map { sessions[$0] }
            ?? AgentSession(id: event.sessionID, cwd: AgentText.sanitized(event.cwd, limit: 1024), state: next, startedAt: now, updatedAt: now)
        if let cwd = event.cwd, !cwd.isEmpty { session.cwd = cwd }
        session.source.merge(event.source)
        if let branch = event.branch, !branch.isEmpty { session.branch = branch }
        if let remote = event.remote { session.remote = remote }
        session.state = next
        session.updatedAt = now
        if let detail = event.detail, !detail.isEmpty { session.detail = detail }
        let warnedBefore = session.contextWarned
        if let usage = event.usage { absorb(usage, into: &session, accumulate: true, now: now, banner: false) }

        if let index {
            var unchanged = session
            unchanged.updatedAt = sessions[index].updatedAt
            if unchanged != sessions[index] || now.timeIntervalSince(sessions[index].updatedAt) >= 1 {
                sessions[index] = session
            }
        } else {
            sessions.append(session)
        }

        if next == .working || next != current {
            NubrixInbox.shared.sessionChanged(id: session.id, project: session.projectWithBranch, state: next, detail: session.detail)
        }

        if next != current, [.done, .failed, .needsAttention].contains(next) {
            show(AgentBanner(sessionID: session.id, project: session.projectWithBranch, state: next))
        }

        if !warnedBefore, session.contextWarned, let percent = session.contextUsedPercent {
            showContextBanner(session, percent: percent)
        }
    }

    func apply(_ update: AgentStatusUpdate) {
        guard Defaults[.claudeEnabled] else { return }
        let now = Date()
        lastStatusAt = now
        if let limits = update.rateLimits, now >= rateLimitsUpdatedAt {
            if rateLimits != limits { rateLimits = limits }
            rateLimitsUpdatedAt = now
        }
        guard let index = sessions.firstIndex(where: { $0.id == update.sessionID }) else { return }
        statusSeen[update.sessionID] = now
        var session = sessions[index]
        if let cwd = update.cwd, !cwd.isEmpty { session.cwd = cwd }
        session.source.merge(update.source)
        if let branch = update.branch, !branch.isEmpty { session.branch = branch }
        if let name = update.modelName { session.modelName = name }
        if let size = update.contextWindowSize { session.contextWindowSize = size }
        if let cost = update.costUSD { session.costUSD = cost }
        if let percent = update.contextUsedPercent { registerContext(percent: percent, in: &session) }
        if session != sessions[index] { sessions[index] = session }
    }

    private func registerContext(percent: Double, in session: inout AgentSession, banner: Bool = true) {
        session.contextUsedPercent = percent
        if percent >= Self.contextWarningThreshold, !session.contextWarned {
            session.contextWarned = true
            NubrixInbox.shared.contextWarning(id: session.id, project: session.projectWithBranch, percent: percent)
            if banner { showContextBanner(session, percent: percent) }
        } else if percent < Self.contextRearmThreshold {
            session.contextWarned = false
        }
    }

    private func showContextBanner(_ session: AgentSession, percent: Double) {
        show(AgentBanner(sessionID: session.id, project: session.projectWithBranch, state: .needsAttention,
                         note: "Context \(Int(percent.rounded()))%"))
    }

    private func absorb(_ usage: AgentUsageSample, into session: inout AgentSession, accumulate: Bool, now: Date, banner: Bool = true) {
        if let model = usage.model { session.usageModel = model }
        session.contextTokens = usage.contextTokens
        let statuslineFresh = statusSeen[session.id].map { now.timeIntervalSince($0) < Self.statusFreshness } ?? false
        if !statuslineFresh, let window = session.contextWindow, window > 0 {
            registerContext(percent: min(100, Double(usage.contextTokens) / Double(window) * 100), in: &session, banner: banner)
        }
        guard accumulate, let turn = usage.turn, turn.messageID != session.lastUsageMessageID else { return }
        session.lastUsageMessageID = turn.messageID
        session.sessionTokens += turn.billableTokens
        let cost = AgentPricing.cost(of: turn, model: usage.model ?? session.usageModel)
        if let cost { session.estimatedCostUSD = (session.estimatedCostUSD ?? 0) + cost }
        recordTurn(session: session.id, tokens: turn.billableTokens, cost: cost ?? 0,
                   model: usage.model ?? session.usageModel, now: now)
    }

    func recordTurn(session id: String, tokens: Int, cost: Double, model: String?, now: Date) {
        ledger.append(ClaudeUsageRecord(date: now, session: ClaudeUsageRecord.sessionHash(id), tokens: tokens,
                                        costUSD: cost, model: model), now: now)
        refreshToday(now: now)
        scheduleLedgerSave()
    }

    private func refreshToday(now: Date) {
        let value = ledger.today(now: now)
        if value != today { today = value }
    }

    private func scheduleLedgerSave() {
        guard ledgerLoaded else {
            ledgerDirty = true
            return
        }
        guard ledgerSaveTask == nil else { return }
        ledgerSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.flushLedger(wait: false)
        }
    }

    func flushLedger(wait: Bool) {
        ledgerSaveTask?.cancel()
        ledgerSaveTask = nil
        guard ledgerLoaded else { return }
        let snapshot = ledger
        let url = ledgerURL
        if wait {
            ledgerQueue.sync { _ = ClaudeUsageLedgerFile.write(snapshot, to: url) }
        } else {
            ledgerQueue.async { _ = ClaudeUsageLedgerFile.write(snapshot, to: url) }
        }
    }

    private struct SummaryCacheKey: Equatable {
        var ledgerVersion: Int
        var limits: AgentRateLimits?
        var limitsUpdatedAt: Date
        var plan: ClaudePlanSnapshot?
        var minute: Int
    }

    func usageSummary(now: Date) -> ClaudeUsageSummary? {
        guard Defaults[.claudeEnabled] else { return nil }
        let plan = ClaudePlanUsageStore.shared.current
        let key = SummaryCacheKey(ledgerVersion: ledgerVersion, limits: rateLimits, limitsUpdatedAt: rateLimitsUpdatedAt,
                                  plan: plan, minute: Int(now.timeIntervalSince1970 / 60))
        if let cache = summaryCache, cache.key == key { return cache.value }
        let value = ClaudeUsageResolver.summary(ledger: ledger, limits: rateLimits, limitsUpdatedAt: rateLimitsUpdatedAt,
                                                plan: plan, now: now)
        summaryCache = (key, value)
        return value
    }

    func showPlanUsageBanner(_ alert: ClaudePlanAlert) {
        guard Defaults[.claudeEnabled] else { return }
        let name = alert.isSession ? ClaudeUsageText.session(Locale.current) : ClaudeUsageText.week(Locale.current)
        show(AgentBanner(sessionID: "plan-usage", project: "Claude",
                         state: alert.threshold >= 95 ? .failed : .needsAttention,
                         note: "\(name) \(ClaudeUsageText.percent(alert.percent))"))
    }

    func session(_ id: String) -> AgentSession? {
        sessions.first { $0.id == id }
    }

    func markWorking(_ id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), sessions[index].state == .needsAttention else { return }
        sessions[index].state = .working
        sessions[index].updatedAt = Date()
        NubrixInbox.shared.sessionChanged(id: id, project: sessions[index].projectWithBranch, state: .working, detail: nil)
    }

    func clearFinished() {
        sessions.removeAll { [.done, .failed, .idle].contains($0.state) }
    }

    func remove(_ id: String) {
        sessions.removeAll { $0.id == id }
    }

    func dismissBanner() {
        bannerTask?.cancel()
        withAnimation(.smooth) { banner = nil }
    }

    private func show(_ next: AgentBanner) {
        guard Defaults[.claudeEnabled], AgentPermissionStore.shared.current == nil else { return }
        DevNotificationStore.shared.dismissBanner()
        ScreenshotBannerStore.shared.dismissBanner()
        bannerTask?.cancel()
        withAnimation(.smooth) { banner = next }
        let duration: Double = next.state == .needsAttention && next.note == nil ? 6 : 4
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.dismissBanner()
        }
    }

    private func sweep() {
        let now = Date()
        let cutoff = now.addingTimeInterval(-retention)
        if sessions.contains(where: { $0.updatedAt < cutoff }) {
            sessions.removeAll { $0.updatedAt < cutoff }
        }
        let live = Set(sessions.map(\.id))
        statusSeen = statusSeen.filter { live.contains($0.key) }
        var pruned = ledger
        pruned.prune(now: now)
        if pruned != ledger {
            ledger = pruned
            scheduleLedgerSave()
        }
        refreshToday(now: now)
    }

    private static func state(after event: AgentHookEvent, current: AgentSessionState?) -> AgentSessionState? {
        switch event.name {
        case "SessionStart":
            return current ?? .idle
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
             "PermissionDenied", "SubagentStart", "PreCompact":
            return .working
        case "PermissionRequest", "Elicitation":
            return .needsAttention
        case "Notification":
            switch event.notificationType {
            case "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
                return .needsAttention
            case "idle_prompt":
                return current == .done || current == .failed ? current : .idle
            default:
                return nil
            }
        case "Stop":
            return .done
        case "StopFailure":
            return .failed
        default:
            return nil
        }
    }
}
