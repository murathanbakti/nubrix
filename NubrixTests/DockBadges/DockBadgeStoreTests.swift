import Combine
import XCTest
@testable import Nubrix

private final class FakeReader: DockBadgeReading {
    var isAvailable = true
    var running: Set<String> = []
    var labels: [String: String] = [:]
    var regularApps: [String] = []
    private(set) var readCount = 0
    private(set) var lastRequested: [String] = []

    func read(bundleIDs: [String]) -> DockBadgeReadResult {
        readCount += 1
        lastRequested = bundleIDs
        return DockBadgeReadResult(running: running.intersection(bundleIDs),
                                   labels: labels.filter { running.contains($0.key) && bundleIDs.contains($0.key) })
    }

    func runningRegularApps() -> [String] { regularApps }
}

@MainActor
private final class FakeScheduler: DockBadgeScheduling {
    private final class Token: DockBadgeCancellable {
        var cancelled = false
        let delay: Double
        let action: @MainActor () -> Void
        init(delay: Double, action: @escaping @MainActor () -> Void) {
            self.delay = delay
            self.action = action
        }
        func cancel() { cancelled = true }
    }

    private var tokens: [Token] = []
    private(set) var scheduledCount = 0

    var pendingCount: Int { tokens.filter { !$0.cancelled }.count }
    var pendingDelays: [Double] { tokens.filter { !$0.cancelled }.map(\.delay) }

    func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> DockBadgeCancellable {
        let token = Token(delay: seconds, action: action)
        tokens.append(token)
        scheduledCount += 1
        return token
    }

    func fire() {
        let due = tokens.filter { !$0.cancelled }
        tokens.removeAll()
        for token in due { token.action() }
    }
}

@MainActor
private final class FakeSettings: DockBadgeSettings {
    var isEnabled = true
    var apps: [String] = ["chat.app", "mail.app"]
}

@MainActor
final class DockBadgeStoreTests: XCTestCase {
    private var reader: FakeReader!
    private var scheduler: FakeScheduler!
    private var settings: FakeSettings!
    private var store: DockBadgeStore!

    override func setUp() async throws {
        reader = FakeReader()
        scheduler = FakeScheduler()
        settings = FakeSettings()
        store = DockBadgeStore(reader: reader, scheduler: scheduler, settings: settings)
    }

    func testDisabledDoesNotReadOrSchedule() {
        settings.isEnabled = false
        reader.running = ["chat.app"]
        reader.labels = ["chat.app": "3"]
        store.start(observingSystem: false)
        XCTAssertEqual(reader.readCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertFalse(store.isPolling)
        XCTAssertEqual(store.status, .off)
        XCTAssertTrue(store.summary.isEmpty)
    }

    func testEnabledWithNothingRunningReadsOnceWithoutTick() {
        store.start(observingSystem: false)
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(reader.lastRequested, ["chat.app", "mail.app"])
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertFalse(store.isPolling)
        XCTAssertEqual(store.status, .ready)
        XCTAssertEqual(store.total, 0)
    }

    func testRunningAppPublishesBadgeAndSchedulesTick() {
        reader.running = ["chat.app"]
        reader.labels = ["chat.app": "3"]
        store.start(observingSystem: false)
        XCTAssertEqual(store.summary.badges.count, 1)
        XCTAssertEqual(store.badge(for: "chat.app")?.count, 3)
        XCTAssertEqual(store.total, 3)
        XCTAssertEqual(store.top?.bundleID, "chat.app")
        XCTAssertTrue(store.isPolling)
        XCTAssertEqual(scheduler.pendingDelays, [3])

        reader.labels["chat.app"] = "5"
        scheduler.fire()
        XCTAssertEqual(reader.readCount, 2)
        XCTAssertEqual(store.badge(for: "chat.app")?.count, 5)
        XCTAssertEqual(scheduler.pendingCount, 1)
    }

    func testRunningAppWithoutLabelHasNoBadgeButKeepsPolling() {
        reader.running = ["chat.app"]
        store.start(observingSystem: false)
        XCTAssertTrue(store.summary.isEmpty)
        XCTAssertEqual(scheduler.pendingCount, 1)
    }

    func testPauseBySleepCancelsTickAndResumeRefreshes() {
        reader.running = ["chat.app"]
        reader.labels = ["chat.app": "3"]
        store.start(observingSystem: false)
        store.setPaused(sleeping: true)
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertFalse(store.isPolling)
        scheduler.fire()
        XCTAssertEqual(reader.readCount, 1)
        store.setPaused(sleeping: false)
        XCTAssertEqual(reader.readCount, 2)
        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertTrue(store.isPolling)
    }

    func testPauseByLockCancelsTickAndResumeRefreshes() {
        reader.running = ["chat.app"]
        reader.labels = ["chat.app": "3"]
        store.start(observingSystem: false)
        store.setPaused(locked: true)
        XCTAssertEqual(scheduler.pendingCount, 0)
        scheduler.fire()
        XCTAssertEqual(reader.readCount, 1)
        store.setPaused(locked: false)
        XCTAssertEqual(reader.readCount, 2)
        XCTAssertEqual(scheduler.pendingCount, 1)
    }

    func testStaysPausedWhileEitherFlagIsSet() {
        reader.running = ["chat.app"]
        reader.labels = ["chat.app": "3"]
        store.start(observingSystem: false)
        store.setPaused(sleeping: true)
        store.setPaused(locked: true)
        store.setPaused(sleeping: false)
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(scheduler.pendingCount, 0)
        store.appEvent(bundleID: "chat.app")
        XCTAssertEqual(reader.readCount, 1)
        store.setPaused(locked: false)
        XCTAssertEqual(reader.readCount, 2)
    }

    func testLaunchOfChosenAppReadsAndSchedules() {
        store.start(observingSystem: false)
        XCTAssertEqual(scheduler.pendingCount, 0)
        reader.running = ["chat.app"]
        reader.labels = ["chat.app": "2"]
        store.appEvent(bundleID: "chat.app")
        XCTAssertEqual(reader.readCount, 2)
        XCTAssertEqual(store.badge(for: "chat.app")?.count, 2)
        XCTAssertEqual(scheduler.pendingCount, 1)
    }

    func testEventsForOtherAppsAreIgnored() {
        store.start(observingSystem: false)
        store.appEvent(bundleID: "other.app")
        store.appEvent(bundleID: nil)
        XCTAssertEqual(reader.readCount, 1)
    }

    func testEventsAreIgnoredWhenDisabled() {
        settings.isEnabled = false
        store.start(observingSystem: false)
        store.appEvent(bundleID: "chat.app")
        XCTAssertEqual(reader.readCount, 0)
    }

    func testQuitRemovesBadgeAndStopsTick() {
        reader.running = ["chat.app"]
        reader.labels = ["chat.app": "3"]
        store.start(observingSystem: false)
        XCTAssertEqual(store.total, 3)
        reader.running = []
        store.appEvent(bundleID: "chat.app")
        XCTAssertNil(store.badge(for: "chat.app"))
        XCTAssertEqual(store.total, 0)
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertFalse(store.isPolling)
    }

    func testUnchangedReadDoesNotPublish() {
        reader.running = ["chat.app"]
        reader.labels = ["chat.app": "3"]
        store.start(observingSystem: false)
        var emissions = 0
        let cancellable = store.objectWillChange.sink { emissions += 1 }
        scheduler.fire()
        scheduler.fire()
        XCTAssertEqual(reader.readCount, 3)
        XCTAssertEqual(emissions, 0)
        reader.labels["chat.app"] = "4"
        scheduler.fire()
        XCTAssertEqual(emissions, 1)
        cancellable.cancel()
    }

    func testUnavailableReaderReportsStatusWithoutReading() {
        reader.isAvailable = false
        reader.running = ["chat.app"]
        reader.labels = ["chat.app": "3"]
        store.start(observingSystem: false)
        XCTAssertEqual(store.status, .unavailable)
        XCTAssertEqual(reader.readCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertTrue(store.summary.isEmpty)
        XCTAssertFalse(store.isAvailable)
    }

    func testUntickingAppRemovesItsBadge() {
        reader.running = ["chat.app", "mail.app"]
        reader.labels = ["chat.app": "3", "mail.app": "1"]
        store.start(observingSystem: false)
        XCTAssertEqual(store.total, 4)
        settings.apps = ["mail.app"]
        store.settingChanged()
        XCTAssertNil(store.badge(for: "chat.app"))
        XCTAssertEqual(store.total, 1)
        XCTAssertEqual(reader.lastRequested, ["mail.app"])
    }

    func testDisablingClearsSummaryAndCancelsTick() {
        reader.running = ["chat.app"]
        reader.labels = ["chat.app": "3"]
        store.start(observingSystem: false)
        settings.isEnabled = false
        store.settingChanged()
        XCTAssertTrue(store.summary.isEmpty)
        XCTAssertEqual(store.status, .off)
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertFalse(store.isPolling)
        scheduler.fire()
        XCTAssertEqual(reader.readCount, 1)
    }

    func testEnablingAfterStartReads() {
        settings.isEnabled = false
        store.start(observingSystem: false)
        settings.isEnabled = true
        reader.running = ["mail.app"]
        reader.labels = ["mail.app": "•"]
        store.settingChanged()
        XCTAssertEqual(store.status, .ready)
        XCTAssertEqual(store.badge(for: "mail.app")?.label, "•")
        XCTAssertEqual(store.total, 1)
    }

    func testEmptyAppListDoesNotRead() {
        settings.apps = []
        store.start(observingSystem: false)
        XCTAssertEqual(reader.readCount, 0)
        XCTAssertEqual(store.status, .ready)
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertTrue(store.summary.isEmpty)
    }

    func testRefreshBeforeStartDoesNothing() {
        store.settingChanged()
        store.refresh()
        XCTAssertEqual(reader.readCount, 0)
        XCTAssertEqual(store.status, .off)
    }

    func testSuggestedAppsComeFromReader() {
        reader.regularApps = ["a", "b"]
        XCTAssertEqual(store.suggestedApps(), ["a", "b"])
    }

    func testOnlyOneTickIsEverPending() {
        reader.running = ["chat.app"]
        reader.labels = ["chat.app": "3"]
        store.start(observingSystem: false)
        store.appEvent(bundleID: "chat.app")
        store.appEvent(bundleID: "chat.app")
        store.settingChanged()
        XCTAssertEqual(scheduler.pendingCount, 1)
    }
}
