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
        case failed(String)
    }

    static let legacyKeys = ["updateAutoCheck", "updateLastCheck", "updateLatestVersion", "updateSkippedVersion"]

    @Published private(set) var buildKind: UpdateBuildKind
    @Published private(set) var automaticallyChecks = false
    @Published private(set) var automaticallyInstalls = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var lastCheck: Date?
    @Published private(set) var status: Status = .idle

    private let defaults: UserDefaults
    private let makeUpdater: (UpdateStore) throws -> UpdaterHandle
    private let activate: () -> Void
    private var handle: UpdaterHandle?

    init(buildKind: UpdateBuildKind,
         defaults: UserDefaults,
         makeUpdater: @escaping (UpdateStore) throws -> UpdaterHandle,
         activate: @escaping () -> Void) {
        self.buildKind = buildKind
        self.defaults = defaults
        self.makeUpdater = makeUpdater
        self.activate = activate
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
    }

    func stop() {
        handle = nil
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
        status = .upToDate
        refresh()
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
