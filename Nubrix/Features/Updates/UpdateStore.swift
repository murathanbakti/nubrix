import AppKit
import Combine
import Defaults

protocol UpdatePreferences: AnyObject {
    var autoCheck: Bool? { get set }
    var lastCheck: Date? { get set }
    var latestVersion: String? { get set }
    var skippedVersion: String? { get set }
}

final class DefaultsUpdatePreferences: UpdatePreferences {
    var autoCheck: Bool? {
        get { Defaults[.updateAutoCheck] }
        set { Defaults[.updateAutoCheck] = newValue }
    }

    var lastCheck: Date? {
        get { Defaults[.updateLastCheck] }
        set { Defaults[.updateLastCheck] = newValue }
    }

    var latestVersion: String? {
        get { Defaults[.updateLatestVersion] }
        set { Defaults[.updateLatestVersion] = newValue }
    }

    var skippedVersion: String? {
        get { Defaults[.updateSkippedVersion] }
        set { Defaults[.updateSkippedVersion] = newValue }
    }
}

enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate
    case available(ReleaseVersion)
    case skipped(ReleaseVersion)
    case failed(UpdateFailure)
}

@MainActor
final class UpdateStore: ObservableObject {
    static let shared: UpdateStore = {
        let client = UpdateClient()
        return UpdateStore(
            preferences: DefaultsUpdatePreferences(),
            currentVersion: Bundle.main.releaseVersionNumber,
            fetch: { try await client.fetchLatest() },
            now: { Date() },
            homebrewProbe: { await XPCHelperClient.shared.isHomebrewInstall() },
            teamIdentifier: { AppSigningIdentity.teamIdentifier() }
        )
    }()

    static let schedulerIdentifier = "dev.nubrix.app.update-check"
    static let checkInterval: TimeInterval = 86_400
    static let checkTolerance: TimeInterval = 3_600
    static let launchDelay: TimeInterval = 20

    @Published private(set) var state: UpdateCheckState = .idle
    @Published private(set) var installKind: UpdateInstallKind
    @Published private(set) var lastCheck: Date?

    private let preferences: UpdatePreferences
    private let currentVersion: ReleaseVersion?
    private let fetch: @Sendable () async throws -> ReleaseVersion
    private let now: () -> Date
    private let homebrewProbe: @Sendable () async -> Bool
    private let teamIdentifier: () -> String?
    private var lastAttempt: Date?
    private var started = false
    private var scheduler: NSBackgroundActivityScheduler?
    private var launchTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var autoCheckCancellable: AnyCancellable?

    init(preferences: UpdatePreferences, currentVersion: String?,
         fetch: @escaping @Sendable () async throws -> ReleaseVersion,
         now: @escaping () -> Date,
         homebrewProbe: @escaping @Sendable () async -> Bool,
         teamIdentifier: @escaping () -> String?) {
        self.preferences = preferences
        self.currentVersion = currentVersion.flatMap { ReleaseVersion(bundleVersion: $0) }
        self.fetch = fetch
        self.now = now
        self.homebrewProbe = homebrewProbe
        self.teamIdentifier = teamIdentifier
        installKind = .resolve(teamIdentifier: teamIdentifier(), isHomebrew: false)
        lastCheck = preferences.lastCheck
        restoreState()
    }

    var autoCheck: Bool? {
        get { preferences.autoCheck }
        set {
            objectWillChange.send()
            preferences.autoCheck = newValue
            if newValue == true { checkIfDue() }
        }
    }

    var availableVersion: ReleaseVersion? {
        if case .available(let version) = state { return version }
        return nil
    }

    func start() {
        guard !started else { return }
        started = true
        installTask = Task { await resolveInstallKind() }
        let scheduler = NSBackgroundActivityScheduler(identifier: Self.schedulerIdentifier)
        scheduler.interval = Self.checkInterval
        scheduler.tolerance = Self.checkTolerance
        scheduler.qualityOfService = .utility
        scheduler.repeats = true
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in self?.checkIfDue() }
            completion(.finished)
        }
        self.scheduler = scheduler
        launchTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.launchDelay))
            guard !Task.isCancelled else { return }
            self?.checkIfDue()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
        autoCheckCancellable = Defaults.publisher(.updateAutoCheck, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.objectWillChange.send()
                if change.newValue == true { self?.checkIfDue() }
            }
    }

    func stop() {
        scheduler?.invalidate()
        scheduler = nil
        launchTask?.cancel()
        launchTask = nil
        installTask?.cancel()
        installTask = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        autoCheckCancellable = nil
        started = false
    }

    func resolveInstallKind() async {
        let team = teamIdentifier()
        installKind = .resolve(teamIdentifier: team, isHomebrew: false)
        guard team == UpdateInstallKind.releaseTeamIdentifier else { return }
        let isHomebrew = await homebrewProbe()
        guard !Task.isCancelled else { return }
        installKind = .resolve(teamIdentifier: team, isHomebrew: isHomebrew)
    }

    @discardableResult
    func checkIfDue() -> Task<Void, Never>? {
        guard UpdateSchedule.isDue(autoCheck: preferences.autoCheck, lastSuccess: lastCheck, lastAttempt: lastAttempt, now: now()) else {
            return nil
        }
        return runCheck()
    }

    @discardableResult
    func checkNow() -> Task<Void, Never>? {
        runCheck()
    }

    func skip() {
        guard case .available(let version) = state else { return }
        preferences.skippedVersion = version.tag
        state = .skipped(version)
    }

    func unskip() {
        preferences.skippedVersion = nil
        guard case .skipped(let version) = state, let currentVersion else { return }
        apply(UpdateDecision.evaluate(latest: version, current: currentVersion, skipped: nil))
    }

    private func runCheck() -> Task<Void, Never>? {
        guard state != .checking else { return nil }
        guard currentVersion != nil else {
            state = .failed(.unknownCurrentVersion)
            return nil
        }
        state = .checking
        lastAttempt = now()
        let fetch = fetch
        return Task { [weak self] in
            let result: Result<ReleaseVersion, UpdateFailure>
            do {
                result = .success(try await fetch())
            } catch let failure as UpdateFailure {
                result = .failure(failure)
            } catch {
                result = .failure(.network)
            }
            self?.finish(result)
        }
    }

    private func finish(_ result: Result<ReleaseVersion, UpdateFailure>) {
        switch result {
        case .success(let latest):
            let date = now()
            preferences.lastCheck = date
            preferences.latestVersion = latest.tag
            lastCheck = date
            guard let currentVersion else {
                state = .failed(.unknownCurrentVersion)
                return
            }
            apply(UpdateDecision.evaluate(latest: latest, current: currentVersion, skipped: preferences.skippedVersion))
        case .failure(let failure):
            state = .failed(failure)
        }
    }

    private func restoreState() {
        guard let currentVersion, let tag = preferences.latestVersion, let latest = ReleaseVersion(tag: tag) else { return }
        apply(UpdateDecision.evaluate(latest: latest, current: currentVersion, skipped: preferences.skippedVersion))
    }

    private func apply(_ verdict: UpdateVerdict) {
        switch verdict {
        case .upToDate: state = .upToDate
        case .available(let version): state = .available(version)
        case .skipped(let version): state = .skipped(version)
        }
    }
}
