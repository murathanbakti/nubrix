import Foundation
import SwiftUI

@MainActor
final class AgentSessionStore: ObservableObject {
    static let shared = AgentSessionStore()

    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var banner: AgentBanner?
    @Published private(set) var rateLimits: AgentRateLimits?

    static let contextWarningThreshold = 85.0
    static let contextRearmThreshold = 70.0
    @Published private(set) var lastHookEventAt: Date?
    @Published private(set) var lastStatusAt: Date?
    @Published private(set) var lastPermissionRequestAt: Date?
    @Published var serverPort: UInt16?
    private var rateLimitsUpdatedAt = Date.distantPast

    private var bannerTask: Task<Void, Never>?
    private var sweepTask: Task<Void, Never>?
    private let retention: TimeInterval = 12 * 60 * 60

    private init() {
        sweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.sweep()
            }
        }
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
        let now = Date()
        lastHookEventAt = now
        if event.name == "SessionEnd" {
            sessions.removeAll { $0.id == event.sessionID }
            NubrixInbox.shared.sessionEnded(id: event.sessionID)
            if banner?.sessionID == event.sessionID { dismissBanner() }
            return
        }

        let index = sessions.firstIndex { $0.id == event.sessionID }
        let current = index.map { sessions[$0].state }
        guard let next = Self.state(after: event, current: current) else { return }

        var session = index.map { sessions[$0] }
            ?? AgentSession(id: event.sessionID, cwd: event.cwd ?? "", state: next, startedAt: now, updatedAt: now)
        if let cwd = event.cwd, !cwd.isEmpty { session.cwd = cwd }
        session.source.merge(event.source)
        if let branch = event.branch, !branch.isEmpty { session.branch = branch }
        if let remote = event.remote { session.remote = remote }
        session.state = next
        session.updatedAt = now
        if let detail = event.detail, !detail.isEmpty { session.detail = detail }

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
    }

    func apply(_ update: AgentStatusUpdate) {
        let now = Date()
        lastStatusAt = now
        if let limits = update.rateLimits, now >= rateLimitsUpdatedAt {
            if rateLimits != limits { rateLimits = limits }
            rateLimitsUpdatedAt = now
        }
        guard let index = sessions.firstIndex(where: { $0.id == update.sessionID }) else { return }
        var session = sessions[index]
        if let cwd = update.cwd, !cwd.isEmpty { session.cwd = cwd }
        session.source.merge(update.source)
        if let branch = update.branch, !branch.isEmpty { session.branch = branch }
        if let name = update.modelName { session.modelName = name }
        if let size = update.contextWindowSize { session.contextWindowSize = size }
        if let cost = update.costUSD { session.costUSD = cost }
        if let percent = update.contextUsedPercent {
            session.contextUsedPercent = percent
            if percent >= Self.contextWarningThreshold, !session.contextWarned {
                session.contextWarned = true
                NubrixInbox.shared.contextWarning(id: session.id, project: session.projectWithBranch, percent: percent)
                show(AgentBanner(sessionID: session.id, project: session.projectWithBranch, state: .needsAttention,
                                 note: "Context \(Int(percent.rounded()))%"))
            } else if percent < Self.contextRearmThreshold {
                session.contextWarned = false
            }
        }
        if session != sessions[index] { sessions[index] = session }
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
        guard AgentPermissionStore.shared.current == nil else { return }
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
        let cutoff = Date().addingTimeInterval(-retention)
        sessions.removeAll { $0.updatedAt < cutoff }
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
