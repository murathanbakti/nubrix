import AppKit
import Defaults
import SwiftUI

@MainActor
final class AgentPermissionStore: ObservableObject {
    static let shared = AgentPermissionStore()
    static let capacity = 5

    @Published private(set) var queue: [AgentPermissionPrompt] = []

    private var replies: [UUID: (AgentPermissionAnswer) -> Void] = [:]
    private var expiries: [UUID: Task<Void, Never>] = [:]

    private init() {}

    var current: AgentPermissionPrompt? { queue.first }

    func submit(_ payload: AgentPermissionPayload, reply: @escaping (AgentPermissionAnswer) -> Void) {
        guard Defaults[.claudeNotchApprovals], queue.count < Self.capacity else {
            reply(.none)
            return
        }
        let prompt = AgentPermissionPrompt(payload: payload, createdAt: Date())
        replies[prompt.id] = reply
        withAnimation(.smooth) { queue.append(prompt) }
        DevNotificationStore.shared.dismissBanner()
        ScreenshotBannerStore.shared.dismissBanner()
        AgentSessionStore.shared.dismissBanner()
        let lifetime = max(2, payload.waitSeconds - 1)
        expiries[prompt.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(lifetime))
            guard !Task.isCancelled else { return }
            self?.finish(prompt.id, answer: .none)
        }
    }

    func allow(_ id: UUID) {
        guard let prompt = queue.first(where: { $0.id == id }) else { return }
        finish(id, answer: .allow)
        AgentSessionStore.shared.markWorking(prompt.payload.sessionID)
    }

    func deny(_ id: UUID) {
        finish(id, answer: .deny)
    }

    func openInSourceApp(_ id: UUID) {
        guard let prompt = queue.first(where: { $0.id == id }) else { return }
        finish(id, answer: .none)
        AgentAppActivator.activate(bundleID: prompt.payload.source.activationBundleID
            ?? AgentSessionStore.shared.session(prompt.payload.sessionID)?.source.activationBundleID)
    }

    func withdraw(_ id: UUID) {
        finish(id, answer: .none)
    }

    func observe(_ event: AgentHookEvent) {
        guard !queue.isEmpty else { return }
        switch event.name {
        case "PostToolUse", "PostToolUseFailure":
            let matching = queue.filter {
                $0.payload.sessionID == event.sessionID
                    && $0.payload.toolName == event.toolName
                    && $0.payload.summary == event.toolSummary
            }
            matching.forEach { finish($0.id, answer: .none) }
        case "PermissionDenied", "UserPromptSubmit", "Stop", "StopFailure", "SessionEnd":
            queue.filter { $0.payload.sessionID == event.sessionID }.forEach { finish($0.id, answer: .none) }
        default:
            break
        }
    }

    func withdrawAll() {
        queue.forEach { finish($0.id, answer: .none) }
    }

    private func finish(_ id: UUID, answer: AgentPermissionAnswer) {
        expiries.removeValue(forKey: id)?.cancel()
        let reply = replies.removeValue(forKey: id)
        if queue.contains(where: { $0.id == id }) {
            withAnimation(.smooth) { queue.removeAll { $0.id == id } }
        }
        reply?(answer)
    }
}
