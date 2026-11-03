import Foundation
@testable import Nubrix

@MainActor
final class FakePermissionClient: PermissionClient {
    var statuses: [AppPermission: PermissionStatus]
    private(set) var statusCalls: [AppPermission] = []
    private(set) var requests: [AppPermission] = []
    private(set) var openedSettings: [AppPermission] = []

    init(statuses: [AppPermission: PermissionStatus] = [:]) {
        self.statuses = statuses
    }

    func status(_ permission: AppPermission) async -> PermissionStatus {
        statusCalls.append(permission)
        return statuses[permission] ?? .notDetermined
    }

    func request(_ permission: AppPermission) async -> PermissionStatus {
        requests.append(permission)
        return statuses[permission] ?? .notDetermined
    }

    func openSystemSettings(_ permission: AppPermission) {
        openedSettings.append(permission)
    }
}

final class RecordingAppleScriptRunner: AppleScriptRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var sources: [String] = []

    var executed: [String] {
        lock.lock()
        defer { lock.unlock() }
        return sources
    }

    func run(_ source: String) async throws -> NSAppleEventDescriptor? {
        lock.lock()
        sources.append(source)
        lock.unlock()
        return nil
    }
}

enum PrivateDefaults {
    static func make() -> (defaults: UserDefaults, name: String) {
        let name = "nubrix.tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    static func destroy(_ name: String) {
        UserDefaults().removePersistentDomain(forName: name)
    }
}
