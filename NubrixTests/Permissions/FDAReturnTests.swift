import XCTest
@testable import Nubrix

@MainActor
final class FDAReturnTests: XCTestCase {
    private var suiteName: String!
    private var suite: UserDefaults!
    private var clock: Date!
    private var fake: FakePermissionClient!

    override func setUp() {
        super.setUp()
        let made = PrivateDefaults.make()
        suite = made.defaults
        suiteName = made.name
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        fake = FakePermissionClient()
    }

    override func tearDown() {
        PrivateDefaults.destroy(suiteName)
        super.tearDown()
    }

    private func flow() -> LaunchFlow {
        LaunchFlow(defaults: suite, now: { [unowned self] in self.clock })
    }

    private func assertOnlyFDAStatusRead(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(fake.statusCalls, [.fullDiskAccess], file: file, line: line)
        XCTAssertTrue(fake.requests.isEmpty, file: file, line: line)
        XCTAssertTrue(fake.openedSettings.isEmpty, file: file, line: line)
    }

    func testPendingGrantSurvivesRelaunchAndBeatsFirstLaunch() {
        flow().beginFDAGrant(origin: .notch)
        XCTAssertEqual(flow().initialAction(musicSourceNeeded: false), .fdaReturn(.notch))
        XCTAssertEqual(flow().initialAction(musicSourceNeeded: true), .fdaReturn(.notch))
    }

    func testGrantedReturnsReadyAndClearsPending() async {
        fake.statuses[.fullDiskAccess] = .granted
        let f = flow()
        f.beginFDAGrant(origin: .notch)
        let outcome = await f.resolveFDAReturn(origin: .notch, client: fake)
        XCTAssertEqual(outcome, .ready(.notch))
        XCTAssertNil(f.pendingFDAOrigin())
        assertOnlyFDAStatusRead()
    }

    func testDeniedReturnsStillOffAndClearsPending() async {
        fake.statuses[.fullDiskAccess] = .denied
        let f = flow()
        f.beginFDAGrant(origin: .settings)
        let outcome = await f.resolveFDAReturn(origin: .settings, client: fake)
        XCTAssertEqual(outcome, .stillOff(.settings))
        XCTAssertNil(f.pendingFDAOrigin())
        assertOnlyFDAStatusRead()
    }

    func testNotDeterminedReturnsStillOff() async {
        fake.statuses[.fullDiskAccess] = .notDetermined
        let f = flow()
        f.beginFDAGrant(origin: .permissions)
        let outcome = await f.resolveFDAReturn(origin: .permissions, client: fake)
        XCTAssertEqual(outcome, .stillOff(.permissions))
        assertOnlyFDAStatusRead()
    }

    func testStalePendingIsIgnored() {
        flow().beginFDAGrant(origin: .notch)
        clock = clock.addingTimeInterval(LaunchFlow.pendingLifetime + 1)
        let f = flow()
        XCTAssertNil(f.pendingFDAOrigin())
        XCTAssertNotEqual(f.initialAction(musicSourceNeeded: false), .fdaReturn(.notch))
    }

    func testPendingJustInsideLifetimeIsHonored() {
        flow().beginFDAGrant(origin: .settings)
        clock = clock.addingTimeInterval(LaunchFlow.pendingLifetime - 1)
        XCTAssertEqual(flow().pendingFDAOrigin(), .settings)
    }

    func testClearFDAPending() {
        let f = flow()
        f.beginFDAGrant(origin: .permissions)
        XCTAssertEqual(f.pendingFDAOrigin(), .permissions)
        f.clearFDAPending()
        XCTAssertNil(f.pendingFDAOrigin())
        XCTAssertNotEqual(f.initialAction(musicSourceNeeded: false), .fdaReturn(.permissions))
    }
}
