import Foundation

enum FDAOrigin: String {
    case settings
    case notch
    case permissions
}

enum LaunchAction: Equatable {
    case none
    case onboarding
    case fdaReturn(FDAOrigin)
}

enum FDAReturnOutcome: Equatable {
    case ready(FDAOrigin)
    case stillOff(FDAOrigin)
}

struct LaunchFlow {
    static let pendingLifetime: TimeInterval = 30 * 60

    private enum Key {
        static let firstLaunch = "firstLaunch"
        static let fdaGrantPendingAt = "fdaGrantPendingAt"
        static let fdaGrantPendingOrigin = "fdaGrantPendingOrigin"
    }

    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    private var firstLaunch: Bool {
        defaults.object(forKey: Key.firstLaunch) == nil ? true : defaults.bool(forKey: Key.firstLaunch)
    }

    func initialAction() -> LaunchAction {
        if let origin = pendingFDAOrigin() { return .fdaReturn(origin) }
        if firstLaunch { return .onboarding }
        return .none
    }

    func onboardingDidAppear() {
        defaults.set(false, forKey: Key.firstLaunch)
    }

    func beginFDAGrant(origin: FDAOrigin) {
        defaults.set(now().timeIntervalSince1970, forKey: Key.fdaGrantPendingAt)
        defaults.set(origin.rawValue, forKey: Key.fdaGrantPendingOrigin)
    }

    func pendingFDAOrigin() -> FDAOrigin? {
        guard defaults.object(forKey: Key.fdaGrantPendingAt) != nil else { return nil }
        let startedAt = defaults.double(forKey: Key.fdaGrantPendingAt)
        let age = now().timeIntervalSince1970 - startedAt
        guard age >= 0, age <= Self.pendingLifetime else { return nil }
        guard let raw = defaults.string(forKey: Key.fdaGrantPendingOrigin) else { return nil }
        return FDAOrigin(rawValue: raw)
    }

    func clearFDAPending() {
        defaults.removeObject(forKey: Key.fdaGrantPendingAt)
        defaults.removeObject(forKey: Key.fdaGrantPendingOrigin)
    }

    @MainActor
    func resolveFDAReturn(origin: FDAOrigin, client: any PermissionClient) async -> FDAReturnOutcome {
        let status = await client.status(.fullDiskAccess)
        clearFDAPending()
        return status == .granted ? .ready(origin) : .stillOff(origin)
    }
}
