import XCTest
@testable import Nubrix

final class HookKitStatusTests: XCTestCase {
    private let names = HookKit.files.map(\.installed)

    private func bundle(_ suffix: String = "v1") -> [String: Data] {
        Dictionary(uniqueKeysWithValues: names.map { ($0, Data("\($0) \(suffix)".utf8)) })
    }

    func testNothingInstalled() {
        XCTAssertEqual(HookKit.evaluate(installed: [:], bundled: bundle()), .notInstalled)
    }

    func testAllEqualIsCurrent() {
        XCTAssertEqual(HookKit.evaluate(installed: bundle(), bundled: bundle()), .current)
    }

    func testOneDifferingFileIsStale() {
        var installed = bundle()
        installed["nubrix-permission"] = Data("old".utf8)
        XCTAssertEqual(HookKit.evaluate(installed: installed, bundled: bundle()), .stale(["nubrix-permission"]))
    }

    func testByteDifferenceCountsEvenWhenLengthMatches() {
        var installed = bundle("v1")
        installed["notchctl"] = Data("notchctl v2".utf8)
        XCTAssertEqual(HookKit.evaluate(installed: installed, bundled: bundle("v1")), .stale(["notchctl"]))
    }

    func testAMissingInstalledFileAmongInstalledOnesIsStale() {
        var installed = bundle()
        installed.removeValue(forKey: "nubrix-statusline")
        XCTAssertEqual(HookKit.evaluate(installed: installed, bundled: bundle()), .stale(["nubrix-statusline"]))
    }

    func testStaleNamesFollowTheFileOrder() {
        let installed = Dictionary(uniqueKeysWithValues: names.map { ($0, Data("old".utf8)) })
        XCTAssertEqual(HookKit.evaluate(installed: installed, bundled: bundle()), .stale(names))
    }

    func testAMissingBundledFileIsUnknownNeverANag() {
        var bundled = bundle()
        bundled.removeValue(forKey: "nubrix-hook")
        XCTAssertEqual(HookKit.evaluate(installed: bundle(), bundled: bundled), .unknown)
        XCTAssertEqual(HookKit.evaluate(installed: [:], bundled: bundled), .unknown)
    }

    func testShouldNotifyMatrix() {
        let stale = HookKitState.stale(["notchctl"])
        XCTAssertTrue(HookKit.shouldNotify(state: stale, lastNotifiedBuild: nil, currentBuild: "4", buildKind: .developerIDRelease))
        XCTAssertTrue(HookKit.shouldNotify(state: stale, lastNotifiedBuild: "3", currentBuild: "4", buildKind: .sourceBuild))
        XCTAssertTrue(HookKit.shouldNotify(state: stale, lastNotifiedBuild: "3", currentBuild: "4", buildKind: .unavailable))
        XCTAssertFalse(HookKit.shouldNotify(state: stale, lastNotifiedBuild: "4", currentBuild: "4", buildKind: .developerIDRelease))
        XCTAssertFalse(HookKit.shouldNotify(state: stale, lastNotifiedBuild: nil, currentBuild: "4", buildKind: .debugBuild))
        XCTAssertFalse(HookKit.shouldNotify(state: stale, lastNotifiedBuild: nil, currentBuild: nil, buildKind: .developerIDRelease))
        for state in [HookKitState.current, .notInstalled, .unknown] {
            XCTAssertFalse(HookKit.shouldNotify(state: state, lastNotifiedBuild: nil, currentBuild: "4", buildKind: .developerIDRelease))
        }
    }

    func testInstallCommandQuotesPathsWithSpaces() {
        XCTAssertEqual(
            HookKit.installCommand(bundlePath: "/Applications/Nubrix.app"),
            "bash /Applications/Nubrix.app/Contents/Resources/nubrix-hooks/scripts/install-hooks.sh"
        )
        XCTAssertEqual(
            HookKit.installCommand(bundlePath: "/Users/me/My Apps/Nubrix.app"),
            "bash '/Users/me/My Apps/Nubrix.app/Contents/Resources/nubrix-hooks/scripts/install-hooks.sh'"
        )
    }

    func testLoadReadsRegularFilesAndSkipsSymlinksAndHugeFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HookKitStatusTests.\(UUID().uuidString)", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        let kit = root.appendingPathComponent("kit", isDirectory: true)
        let fm = FileManager.default
        for file in HookKit.files {
            let source = kit.appendingPathComponent(file.bundled)
            try fm.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("new \(file.installed)".utf8).write(to: source)
        }
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data("new nubrix-hook".utf8).write(to: bin.appendingPathComponent("nubrix-hook"))
        try fm.createSymbolicLink(at: bin.appendingPathComponent("notchctl"), withDestinationURL: kit.appendingPathComponent("cli/notchctl"))
        try Data(count: HookKit.maxFileSize + 1).write(to: bin.appendingPathComponent("nubrix-statusline"))

        let snapshot = HookKit.load(installedDirectory: bin, bundledRoot: kit)
        XCTAssertEqual(Set(snapshot.installed.keys), ["nubrix-hook"])
        XCTAssertEqual(snapshot.bundled.count, HookKit.files.count)
        XCTAssertEqual(
            HookKit.evaluate(installed: snapshot.installed, bundled: snapshot.bundled),
            .stale(["nubrix-permission", "nubrix-statusline", "notchctl"])
        )
    }

    @MainActor
    func testLaunchCheckNotifiesOncePerBuildAndClearsWhenCurrent() async {
        var snapshot = HookKitSnapshot(installed: bundle("old"), bundled: bundle("new"))
        var notified: String?
        var posted: [String] = []
        var cleared: [String] = []
        let store = HookKitStore(
            buildKind: .developerIDRelease,
            currentBuild: "4",
            bundlePath: "/Applications/Nubrix.app",
            load: { [snapshot] in snapshot },
            lastNotifiedBuild: { notified },
            setLastNotifiedBuild: { notified = $0 },
            postNotice: { key, _, _ in posted.append(key) },
            clearNotice: { cleared.append($0) }
        )
        await store.launchCheck()
        XCTAssertEqual(store.state, .stale(names))
        XCTAssertEqual(posted, ["hooks"])
        XCTAssertEqual(notified, "4")
        await store.launchCheck()
        XCTAssertEqual(posted, ["hooks"])
        XCTAssertTrue(cleared.isEmpty)

        snapshot = HookKitSnapshot(installed: bundle("new"), bundled: bundle("new"))
        let fresh = HookKitStore(
            buildKind: .developerIDRelease,
            currentBuild: "4",
            bundlePath: "/Applications/Nubrix.app",
            load: { [snapshot] in snapshot },
            lastNotifiedBuild: { notified },
            setLastNotifiedBuild: { notified = $0 },
            postNotice: { key, _, _ in posted.append(key) },
            clearNotice: { cleared.append($0) }
        )
        await fresh.launchCheck()
        XCTAssertEqual(fresh.state, .current)
        XCTAssertEqual(cleared, ["hooks"])
    }
}
