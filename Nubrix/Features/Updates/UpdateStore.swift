import AppKit
import Combine

@MainActor
final class UpdateStore: ObservableObject {
    static let shared = UpdateStore(
        buildKind: .current,
        defaults: .standard,
        makeUpdater: { try SparkleBridge.make(store: $0) },
        activate: { NSApp.activate(ignoringOtherApps: true) }
    )

    enum Status: Equatable {
        case idle
        case upToDate
        case notInstalled(String)
        case failed(String)
    }

    static let legacyKeys = ["updateAutoCheck", "updateLastCheck", "updateLatestVersion", "updateSkippedVersion"]
    static let lastLaunchedBuildKey = "updateLastLaunchedBuild"
    static let pendingBuildKey = "updatePendingInstallBuild"
    static let pendingVersionKey = "updatePendingInstallVersion"

    @Published private(set) var buildKind: UpdateBuildKind
    @Published private(set) var automaticallyChecks = false
    @Published private(set) var automaticallyInstalls = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var lastCheck: Date?
    @Published private(set) var status: Status = .idle
    @Published private(set) var reminder: UpdateReminder?

    private let defaults: UserDefaults
    private let makeUpdater: (UpdateStore) throws -> UpdaterHandle
    private let activate: () -> Void
    private let currentBuild: String?
    private let scheduleRecheck: @MainActor (@escaping @MainActor () -> Void) -> Void
    private let postNotice: @MainActor (_ key: String, _ title: String, _ message: String) -> Void
    private let clearNotice: @MainActor (_ key: String) -> Void
    private var handle: UpdaterHandle?

    init(buildKind: UpdateBuildKind,
         defaults: UserDefaults,
         makeUpdater: @escaping (UpdateStore) throws -> UpdaterHandle,
         activate: @escaping () -> Void,
         currentBuild: String? = Bundle.main.buildVersionNumber,
         scheduleRecheck: @escaping @MainActor (@escaping @MainActor () -> Void) -> Void = { work in
             DispatchQueue.main.asyncAfter(deadline: .now() + 10) { MainActor.assumeIsolated { work() } }
         },
         postNotice: @escaping @MainActor (_ key: String, _ title: String, _ message: String) -> Void = {
             NubrixInbox.shared.appNotice(key: $0, title: $1, message: $2)
         },
         clearNotice: @escaping @MainActor (_ key: String) -> Void = {
             NubrixInbox.shared.clearAppNotice(key: $0)
         }) {
        self.buildKind = buildKind
        self.defaults = defaults
        self.makeUpdater = makeUpdater
        self.activate = activate
        self.currentBuild = currentBuild
        self.scheduleRecheck = scheduleRecheck
        self.postNotice = postNotice
        self.clearNotice = clearNotice
    }

    var hasUpdater: Bool { handle != nil }

    func start() {
        guard handle == nil else { return }
        guard buildKind.updatesEnabled else {
            migrateLegacyDefaults(updater: nil)
            return
        }
        do {
            handle = try makeUpdater(self)
        } catch {
            status = .failed(error.localizedDescription)
            return
        }
        migrateLegacyDefaults(updater: handle?.updater)
        refresh()
        let previousBuild = defaults.string(forKey: Self.lastLaunchedBuildKey)
        if let currentBuild { defaults.set(currentBuild, forKey: Self.lastLaunchedBuildKey) }
        checkPendingInstall()
        if let previousBuild, let currentBuild, previousBuild != currentBuild,
           handle?.updater.automaticallyChecksForUpdates == true {
            scheduleRecheck { [weak self] in
                guard let updater = self?.handle?.updater, updater.canCheckForUpdates else { return }
                updater.checkForUpdatesInBackground()
            }
        }
    }

    func updateWillInstall(build: String, version: String) {
        defaults.set(build, forKey: Self.pendingBuildKey)
        defaults.set(version, forKey: Self.pendingVersionKey)
    }

    private func checkPendingInstall() {
        guard let pending = defaults.string(forKey: Self.pendingBuildKey), let currentBuild else { return }
        let version = defaults.string(forKey: Self.pendingVersionKey) ?? pending
        defaults.removeObject(forKey: Self.pendingBuildKey)
        defaults.removeObject(forKey: Self.pendingVersionKey)
        let installed: Bool
        if let current = Int(currentBuild), let target = Int(pending) {
            installed = current >= target
        } else {
            installed = currentBuild == pending
        }
        if installed {
            clearNotice("update-install")
        } else {
            status = .notInstalled(version)
            postNotice("update-install", "Nubrix \(version) wasn't installed", "Open Settings, About, and press Check Now to try again. Installed with Homebrew? Run brew upgrade --cask nubrix.")
        }
    }

    func stop() {
        handle = nil
        reminder = nil
    }

    func refresh() {
        guard let updater = handle?.updater else { return }
        automaticallyChecks = updater.automaticallyChecksForUpdates
        automaticallyInstalls = updater.automaticallyDownloadsUpdates
        canCheckForUpdates = updater.canCheckForUpdates
        lastCheck = updater.lastUpdateCheckDate
    }

    func setAutomaticallyChecks(_ on: Bool) {
        guard let updater = handle?.updater else { return }
        if !on {
            updater.automaticallyDownloadsUpdates = false
        }
        updater.automaticallyChecksForUpdates = on
        refresh()
    }

    func setAutomaticallyInstalls(_ on: Bool) {
        guard let updater = handle?.updater, updater.automaticallyChecksForUpdates else { return }
        updater.automaticallyDownloadsUpdates = on
        refresh()
    }

    func checkNow() {
        guard let updater = handle?.updater, updater.canCheckForUpdates else { return }
        activate()
        updater.checkForUpdates()
    }

    func cycleFinished(error: String?) {
        if let error {
            status = .failed(error)
        } else if case .failed = status {
            status = .idle
        }
        refresh()
    }

    func updateFound() {
        status = .idle
        refresh()
    }

    func noUpdateFound() {
        if case .notInstalled = status { clearNotice("update-install") }
        status = .upToDate
        refresh()
    }

    func reminderEvent(_ event: UpdateReminderEvent) {
        let previous = reminder
        reminder = UpdateReminderLogic.reduce(previous, event)
        guard reminder != previous else { return }
        if let reminder {
            if previous?.version != reminder.version {
                postNotice("update", "Nubrix \(reminder.version) is available", "Open Check for Updates in the menu bar, or Settings, About.")
            }
        } else {
            clearNotice("update")
        }
    }

    private func migrateLegacyDefaults(updater: UpdaterControlling?) {
        guard Self.legacyKeys.contains(where: { defaults.object(forKey: $0) != nil }) else { return }
        if let updater,
           defaults.bool(forKey: "updateAutoCheck"),
           defaults.object(forKey: "SUEnableAutomaticChecks") == nil {
            updater.automaticallyChecksForUpdates = true
        }
        for key in Self.legacyKeys { defaults.removeObject(forKey: key) }
    }
}
