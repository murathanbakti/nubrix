import Combine
import Defaults
import Foundation

enum HookKitState: Equatable, Sendable {
    case notInstalled
    case current
    case stale([String])
    case unknown
}

struct HookKitSnapshot: Sendable {
    var installed: [String: Data] = [:]
    var bundled: [String: Data] = [:]
}

enum HookKit {
    static let files: [(installed: String, bundled: String)] = [
        ("nubrix-hook", "claude-plugin/scripts/nubrix-hook"),
        ("nubrix-permission", "claude-plugin/scripts/nubrix-permission"),
        ("nubrix-statusline", "claude-plugin/scripts/nubrix-statusline"),
        ("notchctl", "cli/notchctl"),
    ]
    static let maxFileSize = 1_048_576

    static func evaluate(installed: [String: Data], bundled: [String: Data]) -> HookKitState {
        guard files.allSatisfy({ bundled[$0.installed] != nil }) else { return .unknown }
        guard !installed.isEmpty else { return .notInstalled }
        let stale = files.map(\.installed).filter { installed[$0] != bundled[$0] }
        return stale.isEmpty ? .current : .stale(stale)
    }

    static func shouldNotify(state: HookKitState, lastNotifiedBuild: String?, currentBuild: String?, buildKind: UpdateBuildKind) -> Bool {
        guard case .stale = state, buildKind != .debugBuild, let currentBuild else { return false }
        return lastNotifiedBuild != currentBuild
    }

    static func installCommand(bundlePath: String) -> String {
        ClaudeCodeSettings.installCommand(bundleURL: URL(fileURLWithPath: bundlePath))
    }

    static func readRegularFile(_ url: URL) -> Data? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isSymbolicLink != true,
              values.isRegularFile == true,
              let size = values.fileSize, size <= maxFileSize
        else { return nil }
        return try? Data(contentsOf: url)
    }

    static func load(installedDirectory: URL, bundledRoot: URL) -> HookKitSnapshot {
        var snapshot = HookKitSnapshot()
        for file in files {
            if let data = readRegularFile(installedDirectory.appendingPathComponent(file.installed)) {
                snapshot.installed[file.installed] = data
            }
            if let data = readRegularFile(bundledRoot.appendingPathComponent(file.bundled)) {
                snapshot.bundled[file.installed] = data
            }
        }
        return snapshot
    }
}

@MainActor
final class HookKitStore: ObservableObject {
    static let shared = HookKitStore(
        buildKind: .current,
        currentBuild: Bundle.main.buildVersionNumber,
        bundlePath: Bundle.main.bundleURL.path,
        load: {
            HookKit.load(
                installedDirectory: AgentEventServer.configDirectory.appendingPathComponent("bin", isDirectory: true),
                bundledRoot: Bundle.main.resourceURL?.appendingPathComponent("nubrix-hooks", isDirectory: true)
                    ?? URL(fileURLWithPath: "/nonexistent")
            )
        },
        lastNotifiedBuild: { Defaults[.hookReminderNotifiedBuild] },
        setLastNotifiedBuild: { Defaults[.hookReminderNotifiedBuild] = $0 },
        postNotice: { NubrixInbox.shared.appNotice(key: $0, title: $1, message: $2) },
        clearNotice: { NubrixInbox.shared.clearAppNotice(key: $0) }
    )

    @Published private(set) var state: HookKitState = .unknown

    private let buildKind: UpdateBuildKind
    private let currentBuild: String?
    private let bundlePath: String
    private let load: @Sendable () -> HookKitSnapshot
    private let lastNotifiedBuild: () -> String?
    private let setLastNotifiedBuild: (String?) -> Void
    private let postNotice: @MainActor (_ key: String, _ title: String, _ message: String) -> Void
    private let clearNotice: @MainActor (_ key: String) -> Void

    init(buildKind: UpdateBuildKind,
         currentBuild: String?,
         bundlePath: String,
         load: @escaping @Sendable () -> HookKitSnapshot,
         lastNotifiedBuild: @escaping () -> String?,
         setLastNotifiedBuild: @escaping (String?) -> Void,
         postNotice: @escaping @MainActor (_ key: String, _ title: String, _ message: String) -> Void,
         clearNotice: @escaping @MainActor (_ key: String) -> Void) {
        self.buildKind = buildKind
        self.currentBuild = currentBuild
        self.bundlePath = bundlePath
        self.load = load
        self.lastNotifiedBuild = lastNotifiedBuild
        self.setLastNotifiedBuild = setLastNotifiedBuild
        self.postNotice = postNotice
        self.clearNotice = clearNotice
    }

    var installCommand: String { HookKit.installCommand(bundlePath: bundlePath) }

    var staleNames: [String]? {
        if case .stale(let names) = state { return names }
        return nil
    }

    func refresh() async {
        let load = load
        let snapshot = await Task.detached(priority: .utility) { load() }.value
        state = HookKit.evaluate(installed: snapshot.installed, bundled: snapshot.bundled)
    }

    func launchCheck() async {
        await refresh()
        switch state {
        case .stale:
            guard HookKit.shouldNotify(state: state, lastNotifiedBuild: lastNotifiedBuild(), currentBuild: currentBuild, buildKind: buildKind) else { return }
            postNotice("hooks", "Refresh your Claude Code hooks", "This Nubrix version has newer hook scripts. Settings, About shows the command.")
            setLastNotifiedBuild(currentBuild)
        case .current:
            clearNotice("hooks")
        case .notInstalled, .unknown:
            break
        }
    }
}
