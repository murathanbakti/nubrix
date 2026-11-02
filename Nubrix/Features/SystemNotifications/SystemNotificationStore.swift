import AppKit
import Defaults
import SwiftUI

@MainActor
final class SystemNotificationStore: ObservableObject {
    static let shared = SystemNotificationStore()

    @Published private(set) var status: SystemNotificationStatus = .off
    @Published private(set) var banner: SystemNotificationBanner?
    @Published private(set) var knownApps: [String] = []
    @Published private(set) var history: [SystemNotificationRecord] = []

    private var started = false
    private var sleeping = false
    private var locked = false
    private var cursor: Int64 = -1
    private var generation = 0
    private var fastRecheck = false
    private var loop: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var bannerDeadline = Date()
    private var bannerRemaining: TimeInterval = 6
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var names: [String: String] = [:]
    private var icons: [String: NSImage?] = [:]

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
            setStatus(.waiting)
            restartLoop()
        } else {
            setStatus(.off)
            dismissBanner()
            history = []
            if NubrixCoordinator.shared.currentView == .notifications {
                NubrixCoordinator.shared.currentView = .home
            }
        }
    }

    func checkNow() async -> SystemNotificationStatus {
        guard started, isEnabled else { return status }
        await poll()
        return status
    }

    func setFastRecheck(_ on: Bool) {
        guard fastRecheck != on else { return }
        fastRecheck = on
        if on, isEnabled, [.noAccess, .notFound, .unsupported].contains(status) {
            restartLoop()
        }
    }

    func refreshApps() {
        Task { [weak self] in
            let result = await XPCHelperClient.shared.fetchSystemNotificationApps()
            guard let self, result.status == .ok else { return }
            if self.knownApps != result.apps { self.knownApps = result.apps }
        }
    }

    func dismissBanner() {
        bannerTask?.cancel()
        bannerTask = nil
        guard banner != nil else { return }
        withAnimation(.smooth) { banner = nil }
    }

    func pauseBanner(_ paused: Bool) {
        guard banner != nil else { return }
        if paused {
            guard bannerTask != nil else { return }
            bannerRemaining = max(bannerDeadline.timeIntervalSinceNow, 0)
            bannerTask?.cancel()
            bannerTask = nil
        } else if bannerTask == nil {
            scheduleBannerDismiss(after: max(bannerRemaining, 2))
        }
    }

    func record(matching banner: SystemNotificationBanner) -> SystemNotificationRecord? {
        history.first {
            $0.bundleID == banner.bundleID && $0.body == banner.body && $0.subtitle == banner.subtitle
                && ($0.title == banner.title || ($0.title.isEmpty && banner.title == banner.appName))
        }
    }

    private func scheduleBannerDismiss(after seconds: TimeInterval) {
        bannerTask?.cancel()
        bannerDeadline = Date().addingTimeInterval(seconds)
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismissBanner()
        }
    }

    func openSource(_ banner: SystemNotificationBanner) {
        open(bundleID: banner.bundleID)
        dismissBanner()
    }

    func removeRecord(_ id: UUID) {
        history.removeAll { $0.id == id }
    }

    func clearHistory() {
        history = []
    }

    func open(bundleID: String) {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.bundleURL
        if let url {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        NubrixInbox.shared.markRead(.system)
    }

    func reply(to record: SystemNotificationRecord, text: String) async -> SystemNotificationReplyStatus {
        let status = await XPCHelperClient.shared.replyToNotification(
            recID: record.recID, bundleID: record.bundleID, appName: record.appName, title: record.title, subtitle: record.subtitle, body: record.body, text: text)
        switch status {
        case .sent, .unconfirmed:
            break
        case .notFound, .noAccess, .unsupported, .failed, .gone:
            copyToPasteboard(text)
        }
        return status
    }

    func finishReply(_ status: SystemNotificationReplyStatus, record: SystemNotificationRecord) {
        guard status != .sent else { return }
        if status == .noAccess {
            AccessibilityGuide.begin(resume: record)
        } else {
            open(bundleID: record.bundleID)
        }
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        pasteboard.declareTypes([.string, transient, concealed], owner: nil)
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: transient)
        pasteboard.setData(Data(), forType: concealed)
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
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            icons[bundleID] = .some(nil)
            return nil
        }
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
                case .noAccess, .notFound, .unsupported: interval = self.fastRecheck ? 1.5 : 10
                default: interval = 2
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func setStatus(_ new: SystemNotificationStatus) {
        if status != new { status = new }
    }

    private func poll() async {
        let allowed = Defaults[.systemNotificationApps]
        let current = generation
        let result = await XPCHelperClient.shared.fetchSystemNotifications(after: cursor, allowedApps: allowed)
        guard isEnabled, current == generation else { return }
        switch result.status {
        case .ok:
            setStatus(.ready)
            if result.cursor >= 0 { cursor = result.cursor }
            handle(result.items)
        case .noAccess:
            setStatus(.noAccess)
            cursor = -1
        case .notFound:
            setStatus(.notFound)
        case .unsupported:
            setStatus(.unsupported)
        case .failed:
            setStatus(.failed)
        }
    }

    private func handle(_ items: [SystemNotificationItem]) {
        guard !items.isEmpty else { return }
        let frontmost = Defaults[.systemNotificationsSkipFrontmost] ? NSWorkspace.shared.frontmostApplication?.bundleIdentifier : nil
        let visible = items.filter { $0.bundleID != frontmost }
        guard !visible.isEmpty else { return }
        var newestFresh: SystemNotificationItem?
        for item in visible {
            let name = appName(for: item.bundleID)
            let date = item.date > 0 ? Date(timeIntervalSince1970: item.date) : Date()
            let fresh = Date().timeIntervalSince(date) <= 300
            if fresh {
                let title = item.title.isEmpty ? name : item.title
                let message = [item.subtitle, item.body].filter { !$0.isEmpty }.joined(separator: " ")
                NubrixInbox.shared.system(title: title, message: message.isEmpty ? name : message)
                newestFresh = item
            }
            let record = SystemNotificationRecord(recID: item.id, bundleID: item.bundleID, appName: name, title: item.title,
                                                  subtitle: item.subtitle, body: item.body, date: date)
            history.removeAll { $0.recID == item.id && $0.bundleID == item.bundleID }
            history.insert(record, at: 0)
        }
        if history.count > 50 { history.removeLast(history.count - 50) }
        if let newestFresh { show(newestFresh) }
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
        scheduleBannerDismiss(after: 6)
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
