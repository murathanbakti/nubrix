import AppKit
import Defaults
import SwiftUI

@MainActor
final class SystemNotificationStore: ObservableObject {
    static let shared = SystemNotificationStore()

    @Published private(set) var status: SystemNotificationStatus = .off
    @Published private(set) var banner: SystemNotificationBanner?
    @Published private(set) var knownApps: [String] = []

    private var started = false
    private var sleeping = false
    private var locked = false
    private var cursor: Int64 = -1
    private var generation = 0
    private var loop: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var names: [String: String] = [:]
    private var icons: [String: NSImage] = [:]

    private init() {}

    deinit {
        for (center, token) in observers { center.removeObserver(token) }
    }

    var isEnabled: Bool { Defaults[.systemNotificationsEnabled] }
    private var isPaused: Bool { sleeping || locked }

    func start() {
        guard !started else { return }
        started = true
        registerObservers()
        settingChanged()
    }

    func settingChanged() {
        guard started else { return }
        loop?.cancel()
        loop = nil
        cursor = -1
        generation += 1
        if isEnabled {
            status = .waiting
            restartLoop()
        } else {
            status = .off
            dismissBanner()
        }
    }

    func refreshApps() {
        Task { [weak self] in
            let result = await XPCHelperClient.shared.fetchSystemNotificationApps()
            guard let self, result.status == .ok else { return }
            self.knownApps = result.apps
        }
    }

    func dismissBanner() {
        bannerTask?.cancel()
        guard banner != nil else { return }
        withAnimation(.smooth) { banner = nil }
    }

    func openSource(_ banner: SystemNotificationBanner) {
        let bundleID = banner.bundleID
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            running.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        dismissBanner()
        NubrixInbox.shared.markRead(.system)
    }

    func appName(for bundleID: String) -> String {
        if let cached = names[bundleID] { return cached }
        var name = bundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            var display = FileManager.default.displayName(atPath: url.path)
            if display.hasSuffix(".app") { display.removeLast(4) }
            if !display.isEmpty { name = display }
        }
        names[bundleID] = name
        return name
    }

    func icon(for bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = image
        return image
    }

    private func restartLoop() {
        loop?.cancel()
        guard started, isEnabled, !isPaused else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isEnabled, !self.isPaused else { return }
                await self.poll()
                if Task.isCancelled { return }
                let interval: Double
                switch self.status {
                case .noAccess, .notFound, .unsupported: interval = 10
                default: interval = 2
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func poll() async {
        let allowed = Defaults[.systemNotificationApps]
        let current = generation
        let result = await XPCHelperClient.shared.fetchSystemNotifications(after: cursor, allowedApps: allowed)
        guard isEnabled, current == generation else { return }
        switch result.status {
        case .ok:
            status = .ready
            if result.cursor >= 0 { cursor = result.cursor }
            handle(result.items)
        case .noAccess:
            status = .noAccess
            cursor = -1
        case .notFound:
            status = .notFound
            cursor = -1
        case .unsupported:
            status = .unsupported
            cursor = -1
        case .failed:
            status = .failed
        }
    }

    private func handle(_ items: [SystemNotificationItem]) {
        guard !items.isEmpty else { return }
        let frontmost = Defaults[.systemNotificationsSkipFrontmost] ? NSWorkspace.shared.frontmostApplication?.bundleIdentifier : nil
        let visible = items.filter { $0.bundleID != frontmost }
        guard !visible.isEmpty else { return }
        for item in visible {
            let name = appName(for: item.bundleID)
            let title = item.title.isEmpty ? name : item.title
            let message = [item.subtitle, item.body].filter { !$0.isEmpty }.joined(separator: " ")
            NubrixInbox.shared.system(title: title, message: message.isEmpty ? name : message)
        }
        if let newest = visible.last { show(newest) }
    }

    private func show(_ item: SystemNotificationItem) {
        let name = appName(for: item.bundleID)
        let banner = SystemNotificationBanner(bundleID: item.bundleID, appName: name,
                                              title: item.title.isEmpty ? name : item.title,
                                              subtitle: item.subtitle, body: item.body)
        AgentSessionStore.shared.dismissBanner()
        ScreenshotBannerStore.shared.dismissBanner()
        DevNotificationStore.shared.dismissBanner()
        bannerTask?.cancel()
        withAnimation(.smooth) { self.banner = banner }
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.dismissBanner()
        }
    }

    private func setPaused(sleeping: Bool? = nil, locked: Bool? = nil) {
        let before = isPaused
        if let sleeping { self.sleeping = sleeping }
        if let locked { self.locked = locked }
        if isPaused {
            loop?.cancel()
            loop = nil
        } else if before, isEnabled {
            restartLoop()
        }
    }

    private func registerObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        func watch(_ center: NotificationCenter, _ name: Notification.Name,
                   _ action: @escaping @MainActor @Sendable (SystemNotificationStore) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in if let self { action(self) } }
            }
            observers.append((center, token))
        }
        watch(workspace, NSWorkspace.willSleepNotification) { $0.setPaused(sleeping: true) }
        watch(workspace, NSWorkspace.didWakeNotification) { $0.setPaused(sleeping: false) }
        watch(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.setPaused(locked: true) }
        watch(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.setPaused(locked: false) }
    }
}
