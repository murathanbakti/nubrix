import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
protocol DockBadgeSettings: AnyObject {
    var isEnabled: Bool { get }
    var apps: [String] { get }
}

@MainActor
final class DefaultsDockBadgeSettings: DockBadgeSettings {
    var isEnabled: Bool { Defaults[.dockBadgesEnabled] }
    var apps: [String] { Defaults[.systemNotificationApps] }
}

@MainActor
protocol DockBadgeCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol DockBadgeScheduling: AnyObject {
    func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> DockBadgeCancellable
}

@MainActor
final class TaskDockBadgeScheduler: DockBadgeScheduling {
    private final class Handle: DockBadgeCancellable {
        var task: Task<Void, Never>?
        func cancel() { task?.cancel() }
    }

    func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> DockBadgeCancellable {
        let handle = Handle()
        handle.task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds), tolerance: .seconds(seconds / 4))
            guard !Task.isCancelled else { return }
            action()
        }
        return handle
    }
}

@MainActor
final class DockBadgeStore: ObservableObject {
    static let shared = DockBadgeStore(reader: LaunchServicesDockBadgeReader(),
                                       scheduler: TaskDockBadgeScheduler(),
                                       settings: DefaultsDockBadgeSettings())

    @Published private(set) var status: DockBadgeStatus = .off
    @Published private(set) var summary: DockBadgeSummary = .empty

    private let reader: DockBadgeReading
    private let scheduler: DockBadgeScheduling
    private let settings: DockBadgeSettings
    private let interval: Double

    private var started = false
    private var sleeping = false
    private var locked = false
    private var tick: DockBadgeCancellable?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var settingsCancellable: AnyCancellable?

    init(reader: DockBadgeReading, scheduler: DockBadgeScheduling, settings: DockBadgeSettings, interval: Double = 3) {
        self.reader = reader
        self.scheduler = scheduler
        self.settings = settings
        self.interval = interval
    }

    deinit {
        for (center, token) in observers { center.removeObserver(token) }
    }

    var total: Int { summary.total }
    var top: DockBadge? { summary.top }
    var isEnabled: Bool { settings.isEnabled }
    var isAvailable: Bool { reader.isAvailable }
    private(set) var isPolling = false
    private var isPaused: Bool { sleeping || locked }

    func badge(for bundleID: String) -> DockBadge? {
        summary.badge(for: bundleID)
    }

    func suggestedApps() -> [String] {
        reader.runningRegularApps()
    }

    func start(observingSystem: Bool = true) {
        guard !started else { return }
        started = true
        if observingSystem {
            settingsCancellable = Defaults.publisher(keys: .dockBadgesEnabled, .systemNotificationApps, options: [])
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.settingChanged() }
            registerObservers()
        }
        settingChanged()
    }

    func settingChanged() {
        guard started else { return }
        if !isEnabled {
            cancelTick()
            setSummary(.empty)
            setStatus(.off)
        } else if !reader.isAvailable {
            cancelTick()
            setSummary(.empty)
            setStatus(.unavailable)
        } else {
            refresh()
        }
    }

    func refresh() {
        guard started, isEnabled, !isPaused, reader.isAvailable else { return }
        cancelTick()
        let apps = settings.apps
        guard !apps.isEmpty else {
            setSummary(.empty)
            setStatus(.ready)
            return
        }
        let result = reader.read(bundleIDs: apps)
        var badges: [DockBadge] = []
        var seen = Set<String>()
        for bundleID in apps where result.running.contains(bundleID) && seen.insert(bundleID).inserted {
            if let parsed = DockBadgeLabel.parse(result.labels[bundleID]) {
                badges.append(DockBadge(bundleID: bundleID, label: parsed.label, count: parsed.count))
            }
        }
        setSummary(DockBadgeSummary(badges: badges, order: apps))
        setStatus(.ready)
        if !result.running.isEmpty {
            scheduleTick()
        }
    }

    func appEvent(bundleID: String?) {
        guard let bundleID, isEnabled, !isPaused, settings.apps.contains(bundleID) else { return }
        refresh()
    }

    func setPaused(sleeping: Bool? = nil, locked: Bool? = nil) {
        let before = isPaused
        if let sleeping { self.sleeping = sleeping }
        if let locked { self.locked = locked }
        if isPaused {
            cancelTick()
        } else if before {
            refresh()
        }
    }

    private func scheduleTick() {
        tick = scheduler.schedule(after: interval) { [weak self] in
            self?.tick = nil
            self?.isPolling = false
            self?.refresh()
        }
        isPolling = true
    }

    private func cancelTick() {
        tick?.cancel()
        tick = nil
        isPolling = false
    }

    private func setSummary(_ new: DockBadgeSummary) {
        if summary != new { summary = new }
    }

    private func setStatus(_ new: DockBadgeStatus) {
        if status != new { status = new }
    }

    private func registerObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        func watch(_ center: NotificationCenter, _ name: Notification.Name,
                   _ action: @escaping @MainActor @Sendable (DockBadgeStore, Notification) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let box = NotificationBox(note)
                Task { @MainActor in if let self { action(self, box.note) } }
            }
            observers.append((center, token))
        }
        watch(workspace, NSWorkspace.willSleepNotification) { store, _ in store.setPaused(sleeping: true) }
        watch(workspace, NSWorkspace.didWakeNotification) { store, _ in store.setPaused(sleeping: false) }
        watch(workspace, NSWorkspace.screensDidSleepNotification) { store, _ in store.setPaused(sleeping: true) }
        watch(workspace, NSWorkspace.screensDidWakeNotification) { store, _ in store.setPaused(sleeping: false) }
        watch(workspace, NSWorkspace.sessionDidResignActiveNotification) { store, _ in store.setPaused(locked: true) }
        watch(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { store, _ in store.setPaused(locked: false) }
        watch(distributed, Notification.Name("com.apple.screenIsLocked")) { store, _ in store.setPaused(locked: true) }
        watch(distributed, Notification.Name("com.apple.screenIsUnlocked")) { store, _ in store.setPaused(locked: false) }
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            watch(workspace, name) { store, note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                store.appEvent(bundleID: app?.bundleIdentifier)
            }
        }
    }
}

private final class NotificationBox: @unchecked Sendable {
    let note: Notification
    init(_ note: Notification) { self.note = note }
}
