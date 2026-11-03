import AppKit
import Combine
import Sparkle

@MainActor
protocol UpdaterControlling: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var canCheckForUpdates: Bool { get }
    var lastUpdateCheckDate: Date? { get }
    func checkForUpdates()
}

extension SPUUpdater: UpdaterControlling {}

struct UpdaterHandle {
    let updater: UpdaterControlling
    let retained: [AnyObject]
}

@MainActor
final class SparkleBridge: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private weak var store: UpdateStore?
    private var cancellables: Set<AnyCancellable> = []

    private init(store: UpdateStore) {
        self.store = store
    }

    static func make(store: UpdateStore) throws -> UpdaterHandle {
        let bridge = SparkleBridge(store: store)
        let driver = SPUStandardUserDriver(hostBundle: .main, delegate: bridge)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: bridge)
        try updater.start()
        updater.clearFeedURLFromUserDefaults()
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak store] _ in Task { @MainActor in store?.refresh() } }
            .store(in: &bridge.cancellables)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak store] _ in Task { @MainActor in store?.refresh() } }
            .store(in: &bridge.cancellables)
        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .sink { [weak store] _ in Task { @MainActor in store?.refresh() } }
            .store(in: &bridge.cancellables)
        return UpdaterHandle(updater: updater, retained: [bridge, driver])
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard UpdateBuildKind.current.updatesEnabled else {
            throw NSError(domain: "dev.nubrix.app.updates", code: 1, userInfo: [NSLocalizedDescriptionKey: "Updates are not available in this build."])
        }
    }

    private static let quietErrors: Set<Int> = [
        Int(SUError.noUpdateError.rawValue),
        Int(SUError.installationCanceledError.rawValue),
        Int(SUError.installationAuthorizeLaterError.rawValue),
    ]

    private static func failureText(_ error: (any Error)?) -> String? {
        guard let error else { return nil }
        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain, quietErrors.contains(nsError.code) { return nil }
        return error.localizedDescription
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        store?.cycleFinished(error: Self.failureText(error))
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        store?.updateFound()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        store?.noUpdateFound()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        store?.cycleFinished(error: Self.failureText(error))
    }
}
