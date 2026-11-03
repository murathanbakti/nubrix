import XCTest
@testable import Nubrix

@MainActor
final class FakeUpdater: UpdaterControlling {
    var log: [String] = []
    var checkCount = 0
    var canCheckForUpdates = true
    var lastUpdateCheckDate: Date?
    private var storedDownloads = false

    var automaticallyChecksForUpdates = false {
        didSet { log.append("checks=\(automaticallyChecksForUpdates)") }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { automaticallyChecksForUpdates && storedDownloads }
        set {
            guard automaticallyChecksForUpdates else { return }
            storedDownloads = newValue
            log.append("installs=\(newValue)")
        }
    }

    func checkForUpdates() {
        checkCount += 1
        log.append("check")
    }
}

private struct StartFailure: LocalizedError {
    var errorDescription: String? { "boom" }
}

@MainActor
final class UpdateStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var fake: FakeUpdater!
    private var factoryCalls = 0
    private var activations = 0
    private var posted: [String] = []
    private var cleared: [String] = []

    override func setUp() {
        super.setUp()
        suiteName = "UpdateStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        fake = FakeUpdater()
        factoryCalls = 0
        activations = 0
        posted = []
        cleared = []
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore(_ kind: UpdateBuildKind = .developerIDRelease, failing: Bool = false) -> UpdateStore {
        UpdateStore(
            buildKind: kind,
            defaults: defaults,
            makeUpdater: { [unowned self] _ in
                factoryCalls += 1
                if failing { throw StartFailure() }
                return UpdaterHandle(updater: fake, retained: [])
            },
            activate: { [unowned self] in
                activations += 1
                fake.log.append("activate")
            },
            postNotice: { [unowned self] key, title, _ in posted.append("\(key): \(title)") },
            clearNotice: { [unowned self] key in cleared.append(key) }
        )
    }

    func testNonReleaseBuildsNeverCreateAnUpdaterAndDropLegacyKeys() {
        for kind in [UpdateBuildKind.debugBuild, .sourceBuild, .unavailable] {
            for key in UpdateStore.legacyKeys { defaults.set(true, forKey: key) }
            let store = makeStore(kind)
            store.start()
            XCTAssertEqual(factoryCalls, 0, "\(kind)")
            XCTAssertFalse(store.hasUpdater)
            for key in UpdateStore.legacyKeys { XCTAssertNil(defaults.object(forKey: key), key) }
            store.checkNow()
            store.setAutomaticallyChecks(true)
            XCTAssertEqual(fake.checkCount, 0)
            XCTAssertTrue(fake.log.isEmpty)
        }
    }

    func testDefaultsAreOffAndNothingChecksAtStart() {
        let store = makeStore()
        store.start()
        XCTAssertEqual(factoryCalls, 1)
        XCTAssertFalse(store.automaticallyChecks)
        XCTAssertFalse(store.automaticallyInstalls)
        XCTAssertTrue(store.canCheckForUpdates)
        XCTAssertEqual(fake.checkCount, 0)
        XCTAssertTrue(fake.log.isEmpty)
    }

    func testStartIsIdempotent() {
        let store = makeStore()
        store.start()
        store.start()
        XCTAssertEqual(factoryCalls, 1)
    }

    func testInstallingNeedsChecking() {
        let store = makeStore()
        store.start()
        store.setAutomaticallyInstalls(true)
        XCTAssertFalse(store.automaticallyInstalls)
        XCTAssertTrue(fake.log.isEmpty)
        store.setAutomaticallyChecks(true)
        store.setAutomaticallyInstalls(true)
        XCTAssertTrue(store.automaticallyChecks)
        XCTAssertTrue(store.automaticallyInstalls)
    }

    func testTurningChecksOffClearsInstallsFirstAndTheyStayOffWhenChecksReturn() {
        let store = makeStore()
        store.start()
        store.setAutomaticallyChecks(true)
        store.setAutomaticallyInstalls(true)
        fake.log.removeAll()
        store.setAutomaticallyChecks(false)
        XCTAssertEqual(fake.log, ["installs=false", "checks=false"])
        XCTAssertFalse(store.automaticallyChecks)
        XCTAssertFalse(store.automaticallyInstalls)
        store.setAutomaticallyChecks(true)
        XCTAssertTrue(store.automaticallyChecks)
        XCTAssertFalse(store.automaticallyInstalls)
    }

    func testCheckNowActivatesThenChecks() {
        let store = makeStore()
        store.start()
        store.checkNow()
        XCTAssertEqual(fake.log, ["activate", "check"])
        XCTAssertEqual(activations, 1)
    }

    func testCheckNowDoesNothingWhenSparkleCannotCheck() {
        let store = makeStore()
        store.start()
        fake.canCheckForUpdates = false
        store.refresh()
        XCTAssertFalse(store.canCheckForUpdates)
        store.checkNow()
        XCTAssertEqual(fake.checkCount, 0)
        XCTAssertEqual(activations, 0)
    }

    func testFactoryFailureBecomesAStatus() {
        let store = makeStore(failing: true)
        store.start()
        XCTAssertEqual(store.status, .failed("boom"))
        XCTAssertFalse(store.hasUpdater)
        store.checkNow()
        XCTAssertEqual(activations, 0)
    }

    func testRefreshCopiesTheUpdaterState() {
        let store = makeStore()
        store.start()
        let date = Date(timeIntervalSince1970: 1_000)
        fake.lastUpdateCheckDate = date
        fake.automaticallyChecksForUpdates = true
        store.refresh()
        XCTAssertEqual(store.lastCheck, date)
        XCTAssertTrue(store.automaticallyChecks)
    }

    func testStatusFollowsTheUpdateCycle() {
        let store = makeStore()
        store.start()
        store.noUpdateFound()
        XCTAssertEqual(store.status, .upToDate)
        store.cycleFinished(error: nil)
        XCTAssertEqual(store.status, .upToDate)
        store.cycleFinished(error: "offline")
        XCTAssertEqual(store.status, .failed("offline"))
        store.cycleFinished(error: nil)
        XCTAssertEqual(store.status, .idle)
        store.noUpdateFound()
        store.updateFound()
        XCTAssertEqual(store.status, .idle)
    }

    func testLegacyOptInCarriesOverToChecksButNotInstalls() {
        defaults.set(true, forKey: "updateAutoCheck")
        defaults.set(Date(), forKey: "updateLastCheck")
        defaults.set("v0.1.2", forKey: "updateLatestVersion")
        defaults.set("v0.1.2", forKey: "updateSkippedVersion")
        let store = makeStore()
        store.start()
        XCTAssertTrue(fake.automaticallyChecksForUpdates)
        XCTAssertTrue(store.automaticallyChecks)
        XCTAssertFalse(store.automaticallyInstalls)
        for key in UpdateStore.legacyKeys { XCTAssertNil(defaults.object(forKey: key), key) }
    }

    func testLegacyOptOutOrAbsentAnswerStaysOff() {
        defaults.set(false, forKey: "updateAutoCheck")
        defaults.set("v0.1.2", forKey: "updateLatestVersion")
        let store = makeStore()
        store.start()
        XCTAssertFalse(store.automaticallyChecks)
        XCTAssertTrue(fake.log.isEmpty)
        for key in UpdateStore.legacyKeys { XCTAssertNil(defaults.object(forKey: key), key) }
    }

    func testAnExistingSparkleChoiceWinsOverTheLegacyOne() {
        defaults.set(true, forKey: "updateAutoCheck")
        defaults.set(false, forKey: "SUEnableAutomaticChecks")
        let store = makeStore()
        store.start()
        XCTAssertFalse(store.automaticallyChecks)
        XCTAssertTrue(fake.log.isEmpty)
        XCTAssertNil(defaults.object(forKey: "updateAutoCheck"))
    }

    func testWithoutLegacyKeysNothingIsTouched() {
        defaults.set(false, forKey: "SUEnableAutomaticChecks")
        let store = makeStore()
        store.start()
        XCTAssertTrue(fake.log.isEmpty)
        XCTAssertEqual(defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool, false)
    }

    func testScheduledUpdateCreatesAReminderAndAnInboxNotice() {
        let store = makeStore()
        store.start()
        store.reminderEvent(.willShow(handledBySparkle: false, userInitiated: false, version: "0.2.1", readyToInstall: false))
        XCTAssertEqual(store.reminder, UpdateReminder(version: "0.2.1", readyToInstall: false))
        XCTAssertEqual(posted, ["update: Nubrix 0.2.1 is available"])
        XCTAssertTrue(cleared.isEmpty)
    }

    func testRepeatedEventsForTheSameVersionPostOnce() {
        let store = makeStore()
        store.start()
        let event = UpdateReminderEvent.willShow(handledBySparkle: false, userInitiated: false, version: "0.2.1", readyToInstall: false)
        store.reminderEvent(event)
        store.reminderEvent(.willShow(handledBySparkle: false, userInitiated: false, version: "0.2.1", readyToInstall: true))
        XCTAssertEqual(posted.count, 1)
        XCTAssertEqual(store.reminder?.readyToInstall, true)
    }

    func testUserAttentionClearsTheReminderAndTheNotice() {
        let store = makeStore()
        store.start()
        store.reminderEvent(.willShow(handledBySparkle: false, userInitiated: false, version: "0.2.1", readyToInstall: false))
        store.reminderEvent(.attention)
        XCTAssertNil(store.reminder)
        XCTAssertEqual(cleared, ["update"])
        store.reminderEvent(.sessionFinished)
        XCTAssertEqual(cleared, ["update"])
    }

    func testUserInitiatedChecksPostNothing() {
        let store = makeStore()
        store.start()
        store.reminderEvent(.willShow(handledBySparkle: false, userInitiated: true, version: "0.2.1", readyToInstall: false))
        XCTAssertNil(store.reminder)
        XCTAssertTrue(posted.isEmpty)
    }

    func testStopDropsTheReminder() {
        let store = makeStore()
        store.start()
        store.reminderEvent(.willShow(handledBySparkle: false, userInitiated: false, version: "0.2.1", readyToInstall: false))
        store.stop()
        XCTAssertNil(store.reminder)
    }
}
