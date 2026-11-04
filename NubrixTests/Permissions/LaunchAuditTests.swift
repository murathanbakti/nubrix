import XCTest
@testable import Nubrix

@MainActor
final class LaunchAuditTests: XCTestCase {
    private var fake: FakePermissionClient!
    private var runner: RecordingAppleScriptRunner!
    private var originalClient: (any PermissionClient)!
    private var originalRunner: (any AppleScriptRunning)!
    private var suiteName: String!
    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        fake = FakePermissionClient()
        runner = RecordingAppleScriptRunner()
        originalClient = Permissions.client
        originalRunner = AppleScriptHelper.runner
        Permissions.client = fake
        AppleScriptHelper.runner = runner
        let made = PrivateDefaults.make()
        suite = made.defaults
        suiteName = made.name
    }

    override func tearDown() {
        Permissions.client = originalClient
        AppleScriptHelper.runner = originalRunner
        PrivateDefaults.destroy(suiteName)
        super.tearDown()
    }

    private func assertSilent(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(fake.requests.isEmpty, "requests: \(fake.requests)", file: file, line: line)
        XCTAssertTrue(fake.openedSettings.isEmpty, "opened settings: \(fake.openedSettings)", file: file, line: line)
        XCTAssertTrue(runner.executed.isEmpty, "applescript: \(runner.executed)", file: file, line: line)
    }

    func testFreshDefaultsShowOnboarding() {
        XCTAssertEqual(LaunchFlow(defaults: suite).initialAction(), .onboarding)
        assertSilent()
    }

    func testHUDOffNeedsNoAccessibility() async {
        let ok = await NubrixCoordinator.verifyHUDAtLaunch(hudEnabled: false, client: Permissions.client)
        XCTAssertTrue(ok)
        assertSilent()
    }

    func testHUDOnWithoutAccessibilityFailsWithoutPrompting() async {
        fake.statuses[.accessibility] = .notDetermined
        let ok = await NubrixCoordinator.verifyHUDAtLaunch(hudEnabled: true, client: Permissions.client)
        XCTAssertFalse(ok)
        assertSilent()
    }

    func testHUDOnWithAccessibilityPasses() async {
        fake.statuses[.accessibility] = .granted
        let ok = await NubrixCoordinator.verifyHUDAtLaunch(hudEnabled: true, client: Permissions.client)
        XCTAssertTrue(ok)
        assertSilent()
    }

    func testDeprecatedNowPlayingFallsBackToAnInstalledPlayer() {
        XCTAssertEqual(
            MusicManager.resolvedControllerType(preferred: .nowPlaying, nowPlayingDeprecated: true, spotifyInstalled: true),
            .spotify
        )
        XCTAssertEqual(
            MusicManager.resolvedControllerType(preferred: .nowPlaying, nowPlayingDeprecated: true, spotifyInstalled: false),
            .appleMusic
        )
        XCTAssertEqual(
            MusicManager.resolvedControllerType(preferred: .nowPlaying, nowPlayingDeprecated: false, spotifyInstalled: true),
            .nowPlaying
        )
        XCTAssertEqual(
            MusicManager.resolvedControllerType(preferred: .youtubeMusic, nowPlayingDeprecated: true, spotifyInstalled: true),
            .youtubeMusic
        )
        assertSilent()
    }

    func testSettingsModelRefreshOnlyReadsStatus() async {
        let model = PermissionsSettingsModel(client: fake)
        await model.refresh()
        XCTAssertEqual(model.statuses.count, PermissionsSettingsModel.rows.count)
        assertSilent()
    }

    func testResolveFDAReturnOnlyReadsStatus() async {
        let flow = LaunchFlow(defaults: suite)
        flow.beginFDAGrant(origin: .settings)
        _ = await flow.resolveFDAReturn(origin: .settings, client: Permissions.client)
        assertSilent()
    }

    func testCombinedStoredStatesStaySilent() async {
        let flow = LaunchFlow(defaults: suite)
        flow.onboardingDidAppear()
        flow.beginFDAGrant(origin: .notch)
        fake.statuses[.accessibility] = .notDetermined
        fake.statuses[.fullDiskAccess] = .notDetermined

        XCTAssertEqual(flow.initialAction(), .fdaReturn(.notch))
        let hudOK = await NubrixCoordinator.verifyHUDAtLaunch(hudEnabled: true, client: Permissions.client)
        XCTAssertFalse(hudOK)
        XCTAssertEqual(
            MusicManager.resolvedControllerType(preferred: .nowPlaying, nowPlayingDeprecated: true, spotifyInstalled: false),
            .appleMusic
        )
        let model = PermissionsSettingsModel(client: fake)
        await model.refresh()
        let outcome = await flow.resolveFDAReturn(origin: .notch, client: Permissions.client)
        XCTAssertEqual(outcome, .stillOff(.notch))
        XCTAssertEqual(flow.initialAction(), .none)
        assertSilent()
    }
}
