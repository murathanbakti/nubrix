import Foundation
import SwiftUI

enum AgentSessionState: Int, Comparable {
    case needsAttention
    case working
    case failed
    case done
    case idle

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .needsAttention: return "Needs you"
        case .working: return "Working"
        case .failed: return "Failed"
        case .done: return "Done"
        case .idle: return "Idle"
        }
    }

    var tint: Color {
        switch self {
        case .needsAttention: return .orange
        case .working: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .failed: return .red
        case .done: return .green
        case .idle: return .gray
        }
    }
}

struct AgentSession: Identifiable, Equatable {
    let id: String
    var cwd: String
    var state: AgentSessionState
    var detail: String?
    var startedAt: Date
    var updatedAt: Date

    var project: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty || name == "/" ? "Claude" : name
    }
}

struct AgentBanner: Equatable {
    let sessionID: String
    let project: String
    let state: AgentSessionState
}

struct AgentHookEvent {
    let name: String
    let sessionID: String
    let cwd: String?
    let notificationType: String?
    let detail: String?

    init?(json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let name = object["hook_event_name"] as? String,
              let sessionID = object["session_id"] as? String, !sessionID.isEmpty
        else { return nil }
        self.name = name
        self.sessionID = sessionID
        cwd = object["cwd"] as? String
        notificationType = object["notification_type"] as? String
        let raw = (object["last_assistant_message"] as? String)
            ?? (object["message"] as? String)
            ?? (object["prompt"] as? String)
            ?? (object["tool_name"] as? String)
        detail = raw.map(Self.summarize)
    }

    private static func summarize(_ text: String) -> String {
        let line = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return line.count > 160 ? String(line.prefix(159)) + "…" : line
    }
}

@MainActor
final class AgentSessionStore: ObservableObject {
    static let shared = AgentSessionStore()

    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var banner: AgentBanner?

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

    func apply(_ event: AgentHookEvent) {
        let now = Date()
        if event.name == "SessionEnd" {
            sessions.removeAll { $0.id == event.sessionID }
            if banner?.sessionID == event.sessionID { dismissBanner() }
            return
        }

        let index = sessions.firstIndex { $0.id == event.sessionID }
        let current = index.map { sessions[$0].state }
        guard let next = Self.state(after: event, current: current) else { return }

        var session = index.map { sessions[$0] }
            ?? AgentSession(id: event.sessionID, cwd: event.cwd ?? "", state: next, startedAt: now, updatedAt: now)
        if let cwd = event.cwd, !cwd.isEmpty { session.cwd = cwd }
        session.state = next
        session.updatedAt = now
        if let detail = event.detail, !detail.isEmpty { session.detail = detail }

        if let index { sessions[index] = session } else { sessions.append(session) }

        if next != current, [.done, .failed, .needsAttention].contains(next) {
            show(AgentBanner(sessionID: session.id, project: session.project, state: next))
        }
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
        DevNotificationStore.shared.dismissBanner()
        bannerTask?.cancel()
        withAnimation(.smooth) { banner = next }
        let duration: Double = next.state == .needsAttention ? 6 : 4
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
