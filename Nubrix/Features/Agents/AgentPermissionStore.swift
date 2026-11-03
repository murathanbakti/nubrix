import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class AgentPermissionStore: ObservableObject {
    static let shared = AgentPermissionStore()
    static let capacity = 5
    static let minimumDisplay: TimeInterval = 0.7

    @Published private(set) var queue: [AgentPermissionPrompt] = []
    @Published private(set) var isSuppressed = false

    private var replies: [UUID: (AgentPermissionAnswer) -> Void] = [:]
    private var expiries: [UUID: Task<Void, Never>] = [:]
    private var shownAt: [UUID: TimeInterval] = [:]

    private var suppressionReasons: Set<String> = []
    private var surfaces: [String: Bool] = [:]
    private var observers: [NSObjectProtocol] = []
    private var policyCancellable: AnyCancellable?

    private init() {
        installObservers()
        policyCancellable = Defaults.publisher(keys: .claudeNotchApprovals, .claudeEnabled, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self, !Self.isAllowed else { return }
                self.withdrawAll()
            }
    }

    private static var isAllowed: Bool {
        Defaults[.claudeEnabled] && Defaults[.claudeNotchApprovals]
    }

    var current: AgentPermissionPrompt? { isSuppressed || !Self.isAllowed ? nil : queue.first }

    var canPresent: Bool {
        Self.isAllowed && !isSuppressed && surfaces.values.contains(true)
    }

    func setPresentable(_ presentable: Bool, surface: String) {
        guard surfaces[surface] != presentable else { return }
        surfaces[surface] = presentable
    }

    func removeSurface(_ surface: String) {
        surfaces.removeValue(forKey: surface)
    }

    private func suppress(_ reason: String) {
        suppressionReasons.insert(reason)
        isSuppressed = true
        withdrawAll()
    }

    private func resume(_ reason: String) {
        suppressionReasons.remove(reason)
        isSuppressed = !suppressionReasons.isEmpty
    }

    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, Notification.Name, String)] = [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "sleep"),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "screens"),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "session"),
        ]
        for (begin, end, reason) in pairs {
            observers.append(workspace.addObserver(forName: begin, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AgentPermissionStore.shared.suppress(reason) }
            })
            observers.append(workspace.addObserver(forName: end, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AgentPermissionStore.shared.resume(reason) }
            })
        }
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AgentPermissionStore.shared.suppress("lock") }
        })
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AgentPermissionStore.shared.resume("lock") }
        })
    }

    func submit(_ payload: AgentPermissionPayload, reply: @escaping (AgentPermissionAnswer) -> Void) {
        guard canPresent, queue.count < Self.capacity else {
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

    func noteShown(_ id: UUID) {
        guard !isSuppressed, shownAt[id] == nil, queue.contains(where: { $0.id == id }) else { return }
        shownAt[id] = ProcessInfo.processInfo.systemUptime
    }

    func allow(_ id: UUID) {
        guard !isSuppressed, let prompt = queue.first(where: { $0.id == id }),
              let shown = shownAt[id],
              ProcessInfo.processInfo.systemUptime - shown >= Self.minimumDisplay
        else { return }
        finish(id, answer: .allow)
        AgentSessionStore.shared.markWorking(prompt.payload.sessionID)
    }

    func deny(_ id: UUID) {
        finish(id, answer: .deny)
    }

    func openInSourceApp(_ id: UUID) {
        guard let prompt = queue.first(where: { $0.id == id }) else { return }
        finish(id, answer: .none)
        let session = AgentSessionStore.shared.session(prompt.payload.sessionID)
        var source = session?.source ?? AgentSourceInfo()
        source.merge(prompt.payload.source)
        AgentSessionOpener.open(source, cwd: session?.cwd ?? prompt.payload.cwd)
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
                    && (event.toolKey == nil || $0.payload.matchKey == event.toolKey)
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
        shownAt.removeValue(forKey: id)
        let reply = replies.removeValue(forKey: id)
        if queue.contains(where: { $0.id == id }) {
            withAnimation(.smooth) { queue.removeAll { $0.id == id } }
        }
        reply?(answer)
    }
}
