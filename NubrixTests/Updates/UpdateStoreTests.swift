import Combine
import XCTest
@testable import Nubrix

final class InMemoryUpdatePreferences: UpdatePreferences {
    var autoCheck: Bool?
    var lastCheck: Date?
    var latestVersion: String?
    var skippedVersion: String?

    init(autoCheck: Bool? = nil, lastCheck: Date? = nil, latestVersion: String? = nil, skippedVersion: String? = nil) {
        self.autoCheck = autoCheck
        self.lastCheck = lastCheck
        self.latestVersion = latestVersion
        self.skippedVersion = skippedVersion
    }
}

final class UpdateFetchStub: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var outcome: Result<ReleaseVersion, UpdateFailure>

    init(_ outcome: Result<ReleaseVersion, UpdateFailure>) {
        self.outcome = outcome
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func set(_ outcome: Result<ReleaseVersion, UpdateFailure>) {
        lock.lock()
        defer { lock.unlock() }
        self.outcome = outcome
    }

    func fetch() async throws -> ReleaseVersion {
        let current: Result<ReleaseVersion, UpdateFailure> = {
            lock.lock()
            defer { lock.unlock() }
            calls += 1
            return outcome
        }()
        return try current.get()
    }
}

final class UpdateProbeStub: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    let answer: Bool

    init(answer: Bool) {
        self.answer = answer
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func probe() async -> Bool {
        lock.lock()
        calls += 1
        lock.unlock()
        return answer
    }
}

final class UpdateClockBox {
    var date: Date

    init(_ date: Date) {
        self.date = date
    }
}

@MainActor
final class UpdateStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let v011 = ReleaseVersion(major: 0, minor: 1, patch: 1)
    private let v020 = ReleaseVersion(major: 0, minor: 2, patch: 0)

    private struct Harness {
        let store: UpdateStore
        let prefs: InMemoryUpdatePreferences
        let fetch: UpdateFetchStub
        let probe: UpdateProbeStub
        let clock: UpdateClockBox
    }

    private func makeHarness(prefs: InMemoryUpdatePreferences = InMemoryUpdatePreferences(),
                             current: String? = "0.1.1",
                             outcome: Result<ReleaseVersion, UpdateFailure>? = nil,
                             team: String? = "ABCDE12345",
                             isHomebrew: Bool = false) -> Harness {
        let fetch = UpdateFetchStub(outcome ?? .success(v020))
        let probe = UpdateProbeStub(answer: isHomebrew)
        let clock = UpdateClockBox(now)
        let store = UpdateStore(
            preferences: prefs,
            currentVersion: current,
            fetch: { try await fetch.fetch() },
            now: { clock.date },
            homebrewProbe: { await probe.probe() },
            teamIdentifier: { team }
        )
        return Harness(store: store, prefs: prefs, fetch: fetch, probe: probe, clock: clock)
    }

    func testInitialStateIsIdleWithoutStoredVersion() {
        let h = makeHarness()
        XCTAssertEqual(h.store.state, .idle)
        XCTAssertNil(h.store.availableVersion)
        XCTAssertNil(h.store.lastCheck)
        XCTAssertEqual(h.fetch.count, 0)
    }

    func testCheckIfDueDoesNothingWhenAutoCheckNil() {
        let h = makeHarness(prefs: InMemoryUpdatePreferences(autoCheck: nil))
        XCTAssertNil(h.store.checkIfDue())
        XCTAssertEqual(h.fetch.count, 0)
        XCTAssertEqual(h.store.state, .idle)
    }

    func testCheckIfDueDoesNothingWhenAutoCheckFalse() {
        let h = makeHarness(prefs: InMemoryUpdatePreferences(autoCheck: false))
        XCTAssertNil(h.store.checkIfDue())
        XCTAssertEqual(h.fetch.count, 0)
    }

    func testCheckIfDueSkipsAfterRecentSuccess() {
        let prefs = InMemoryUpdatePreferences(autoCheck: true, lastCheck: now.addingTimeInterval(-3_600))
        let h = makeHarness(prefs: prefs)
        XCTAssertNil(h.store.checkIfDue())
        XCTAssertEqual(h.fetch.count, 0)
    }

    func testCheckIfDueFetchesAfter25Hours() async {
        let prefs = InMemoryUpdatePreferences(autoCheck: true, lastCheck: now.addingTimeInterval(-25 * 3_600))
        let h = makeHarness(prefs: prefs)
        let task = h.store.checkIfDue()
        XCTAssertNotNil(task)
        XCTAssertEqual(h.store.state, .checking)
        await task?.value
        XCTAssertEqual(h.fetch.count, 1)
        XCTAssertEqual(h.store.state, .available(v020))
    }

    func testCheckIfDueFetchesWhenNeverChecked() async {
        let h = makeHarness(prefs: InMemoryUpdatePreferences(autoCheck: true))
        await h.store.checkIfDue()?.value
        XCTAssertEqual(h.fetch.count, 1)
    }

    func testCheckNowFetchesEvenWhenOff() async {
        let h = makeHarness(prefs: InMemoryUpdatePreferences(autoCheck: nil))
        let task = h.store.checkNow()
        XCTAssertNotNil(task)
        await task?.value
        XCTAssertEqual(h.fetch.count, 1)
        XCTAssertEqual(h.store.state, .available(v020))
        XCTAssertNil(h.prefs.autoCheck)
    }

    func testCheckNowFetchesEvenWithRecentSuccess() async {
        let prefs = InMemoryUpdatePreferences(autoCheck: true, lastCheck: now.addingTimeInterval(-60))
        let h = makeHarness(prefs: prefs)
        await h.store.checkNow()?.value
        XCTAssertEqual(h.fetch.count, 1)
    }

    func testSuccessWritesLastCheckAndLatest() async {
        let h = makeHarness()
        await h.store.checkNow()?.value
        XCTAssertEqual(h.prefs.lastCheck, now)
        XCTAssertEqual(h.prefs.latestVersion, "v0.2.0")
        XCTAssertEqual(h.store.lastCheck, now)
        XCTAssertEqual(h.store.availableVersion, v020)
    }

    func testSuccessWithSameVersionIsUpToDate() async {
        let h = makeHarness(outcome: .success(v011))
        await h.store.checkNow()?.value
        XCTAssertEqual(h.store.state, .upToDate)
        XCTAssertNil(h.store.availableVersion)
        XCTAssertEqual(h.prefs.latestVersion, "v0.1.1")
    }

    func testSuccessWithSkippedVersionIsSkipped() async {
        let h = makeHarness(prefs: InMemoryUpdatePreferences(skippedVersion: "v0.2.0"))
        await h.store.checkNow()?.value
        XCTAssertEqual(h.store.state, .skipped(v020))
        XCTAssertNil(h.store.availableVersion)
    }

    func testFailureSetsFailedAndWritesNothing() async {
        let prefs = InMemoryUpdatePreferences(lastCheck: now.addingTimeInterval(-90_000), latestVersion: "v0.1.1")
        let h = makeHarness(prefs: prefs, outcome: .failure(.network))
        await h.store.checkNow()?.value
        XCTAssertEqual(h.store.state, .failed(.network))
        XCTAssertEqual(h.prefs.lastCheck, now.addingTimeInterval(-90_000))
        XCTAssertEqual(h.prefs.latestVersion, "v0.1.1")
        XCTAssertEqual(h.store.lastCheck, now.addingTimeInterval(-90_000))
    }

    func testFailureOnFreshPrefsWritesNothing() async {
        let h = makeHarness(outcome: .failure(.http(500)))
        await h.store.checkNow()?.value
        XCTAssertEqual(h.store.state, .failed(.http(500)))
        XCTAssertNil(h.prefs.lastCheck)
        XCTAssertNil(h.prefs.latestVersion)
        XCTAssertNil(h.store.lastCheck)
    }

    func testCheckIfDueDoesNotRetryRightAfterFailure() async {
        let h = makeHarness(prefs: InMemoryUpdatePreferences(autoCheck: true), outcome: .failure(.network))
        await h.store.checkIfDue()?.value
        XCTAssertEqual(h.fetch.count, 1)
        h.clock.date = now.addingTimeInterval(600)
        XCTAssertNil(h.store.checkIfDue())
        XCTAssertEqual(h.fetch.count, 1)
        XCTAssertEqual(h.store.state, .failed(.network))
    }

    func testCheckIfDueRetriesAfterRetryWindow() async {
        let h = makeHarness(prefs: InMemoryUpdatePreferences(autoCheck: true), outcome: .failure(.network))
        await h.store.checkIfDue()?.value
        h.clock.date = now.addingTimeInterval(3_601)
        await h.store.checkIfDue()?.value
        XCTAssertEqual(h.fetch.count, 2)
    }

    func testCheckNowIgnoresRetryWindowAfterFailure() async {
        let h = makeHarness(outcome: .failure(.network))
        await h.store.checkNow()?.value
        await h.store.checkNow()?.value
        XCTAssertEqual(h.fetch.count, 2)
    }

    func testTriggerWhileCheckingIsIgnored() async {
        let h = makeHarness()
        let first = h.store.checkNow()
        XCTAssertNotNil(first)
        XCTAssertNil(h.store.checkNow())
        await first?.value
        XCTAssertEqual(h.fetch.count, 1)
    }

    func testRecoversAfterFailure() async {
        let h = makeHarness(outcome: .failure(.network))
        await h.store.checkNow()?.value
        h.fetch.set(.success(v020))
        await h.store.checkNow()?.value
        XCTAssertEqual(h.store.state, .available(v020))
        XCTAssertEqual(h.prefs.lastCheck, now)
    }

    func testSkipFromAvailable() async {
        let h = makeHarness()
        await h.store.checkNow()?.value
        h.store.skip()
        XCTAssertEqual(h.prefs.skippedVersion, "v0.2.0")
        XCTAssertEqual(h.store.state, .skipped(v020))
        XCTAssertNil(h.store.availableVersion)
    }

    func testSkipOutsideAvailableDoesNothing() {
        let h = makeHarness()
        h.store.skip()
        XCTAssertNil(h.prefs.skippedVersion)
        XCTAssertEqual(h.store.state, .idle)
    }

    func testUnskipRestoresAvailable() async {
        let h = makeHarness()
        await h.store.checkNow()?.value
        h.store.skip()
        h.store.unskip()
        XCTAssertNil(h.prefs.skippedVersion)
        XCTAssertEqual(h.store.state, .available(v020))
        XCTAssertEqual(h.store.availableVersion, v020)
    }

    func testNewerReleaseAfterSkipIsAvailableAgain() async {
        let h = makeHarness()
        await h.store.checkNow()?.value
        h.store.skip()
        let v030 = ReleaseVersion(major: 0, minor: 3, patch: 0)
        h.fetch.set(.success(v030))
        await h.store.checkNow()?.value
        XCTAssertEqual(h.store.state, .available(v030))
    }

    func testRestoreUpToDateWhenStoredEqualsCurrent() {
        let h = makeHarness(prefs: InMemoryUpdatePreferences(latestVersion: "v0.1.1"))
        XCTAssertEqual(h.store.state, .upToDate)
    }

    func testRestoreAvailableWhenStoredNewer() {
        let h = makeHarness(prefs: InMemoryUpdatePreferences(latestVersion: "v0.2.0"))
        XCTAssertEqual(h.store.state, .available(v020))
        XCTAssertEqual(h.store.availableVersion, v020)
    }

    func testRestoreSkippedWhenStoredSkipped() {
        let h = makeHarness(prefs: InMemoryUpdatePreferences(latestVersion: "v0.2.0", skippedVersion: "v0.2.0"))
        XCTAssertEqual(h.store.state, .skipped(v020))
    }

    func testRestoreUpToDateAfterUserUpdated() {
        let h = makeHarness(prefs: InMemoryUpdatePreferences(latestVersion: "v0.2.0"), current: "0.2.0")
        XCTAssertEqual(h.store.state, .upToDate)
    }

    func testRestoreIgnoresInvalidStoredTag() {
        let h = makeHarness(prefs: InMemoryUpdatePreferences(latestVersion: "1.2.3-beta"))
        XCTAssertEqual(h.store.state, .idle)
    }

    func testRestoreSkippedForOtherVersionStaysAvailable() {
        let h = makeHarness(prefs: InMemoryUpdatePreferences(latestVersion: "v0.3.0", skippedVersion: "v0.2.0"))
        XCTAssertEqual(h.store.state, .available(ReleaseVersion(major: 0, minor: 3, patch: 0)))
    }

    func testRestoreExposesStoredLastCheck() {
        let date = now.addingTimeInterval(-500)
        let h = makeHarness(prefs: InMemoryUpdatePreferences(lastCheck: date))
        XCTAssertEqual(h.store.lastCheck, date)
    }

    func testUnparseableCurrentVersionFailsOnCheckNow() {
        let h = makeHarness(current: "garbage")
        let task = h.store.checkNow()
        XCTAssertNil(task)
        XCTAssertEqual(h.store.state, .failed(.unknownCurrentVersion))
        XCTAssertEqual(h.fetch.count, 0)
    }

    func testNilCurrentVersionFailsOnCheckNow() {
        let h = makeHarness(current: nil)
        XCTAssertNil(h.store.checkNow())
        XCTAssertEqual(h.store.state, .failed(.unknownCurrentVersion))
        XCTAssertEqual(h.fetch.count, 0)
    }

    func testUnparseableCurrentVersionFailsOnDueCheck() {
        let h = makeHarness(prefs: InMemoryUpdatePreferences(autoCheck: true), current: "garbage")
        XCTAssertNil(h.store.checkIfDue())
        XCTAssertEqual(h.store.state, .failed(.unknownCurrentVersion))
        XCTAssertEqual(h.fetch.count, 0)
    }

    func testUnparseableCurrentVersionDoesNotRestoreState() {
        let h = makeHarness(prefs: InMemoryUpdatePreferences(latestVersion: "v0.2.0"), current: "garbage")
        XCTAssertEqual(h.store.state, .idle)
    }

    func testNonReleaseTeamIsSourceBuildAndNeverProbes() async {
        let h = makeHarness(team: "ABCDE12345", isHomebrew: true)
        XCTAssertEqual(h.store.installKind, .sourceBuild)
        await h.store.resolveInstallKind()
        XCTAssertEqual(h.store.installKind, .sourceBuild)
        XCTAssertEqual(h.probe.count, 0)
    }

    func testNilTeamIsSourceBuildAndNeverProbes() async {
        let h = makeHarness(team: nil, isHomebrew: true)
        await h.store.resolveInstallKind()
        XCTAssertEqual(h.store.installKind, .sourceBuild)
        XCTAssertEqual(h.probe.count, 0)
    }

    func testReleaseTeamWithHomebrewProbeIsHomebrew() async {
        let h = makeHarness(team: UpdateInstallKind.releaseTeamIdentifier, isHomebrew: true)
        XCTAssertEqual(h.store.installKind, .releaseZip)
        await h.store.resolveInstallKind()
        XCTAssertEqual(h.store.installKind, .homebrew)
        XCTAssertEqual(h.probe.count, 1)
    }

    func testReleaseTeamWithoutHomebrewProbeIsReleaseZip() async {
        let h = makeHarness(team: UpdateInstallKind.releaseTeamIdentifier, isHomebrew: false)
        await h.store.resolveInstallKind()
        XCTAssertEqual(h.store.installKind, .releaseZip)
        XCTAssertEqual(h.probe.count, 1)
    }

    func testEnablingAutoCheckTriggersDueCheck() async {
        let h = makeHarness()
        let finished = expectation(description: "check finished")
        let target = v020
        let cancellable = h.store.$state.filter { $0 == .available(target) }.sink { _ in finished.fulfill() }
        h.store.autoCheck = true
        XCTAssertEqual(h.prefs.autoCheck, true)
        XCTAssertEqual(h.store.state, .checking)
        await fulfillment(of: [finished], timeout: 5)
        cancellable.cancel()
        XCTAssertEqual(h.fetch.count, 1)
        XCTAssertEqual(h.store.state, .available(v020))
    }

    func testDisablingAutoCheckDoesNotFetch() {
        let h = makeHarness(prefs: InMemoryUpdatePreferences(autoCheck: true))
        h.store.autoCheck = false
        XCTAssertEqual(h.prefs.autoCheck, false)
        XCTAssertEqual(h.fetch.count, 0)
        XCTAssertEqual(h.store.state, .idle)
    }
}
