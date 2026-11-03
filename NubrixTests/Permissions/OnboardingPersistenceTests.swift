import XCTest
@testable import Nubrix

final class OnboardingPersistenceTests: XCTestCase {
    private var suiteName: String!
    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        let made = PrivateDefaults.make()
        suite = made.defaults
        suiteName = made.name
    }

    override func tearDown() {
        PrivateDefaults.destroy(suiteName)
        super.tearDown()
    }

    func testOnboardingShownOnceAcrossRelaunch() {
        let first = LaunchFlow(defaults: suite)
        XCTAssertEqual(first.initialAction(musicSourceNeeded: false), .onboarding)
        first.onboardingDidAppear()
        let relaunched = LaunchFlow(defaults: suite)
        XCTAssertEqual(relaunched.initialAction(musicSourceNeeded: false), .none)
    }

    func testOnboardingRepeatsUntilItAppears() {
        XCTAssertEqual(LaunchFlow(defaults: suite).initialAction(musicSourceNeeded: false), .onboarding)
        XCTAssertEqual(LaunchFlow(defaults: suite).initialAction(musicSourceNeeded: false), .onboarding)
    }

    func testMusicSourceShownOnceAcrossRelaunch() {
        LaunchFlow(defaults: suite).onboardingDidAppear()
        let first = LaunchFlow(defaults: suite)
        XCTAssertEqual(first.initialAction(musicSourceNeeded: true), .musicSource)
        first.musicSourceDidAppear()
        let relaunched = LaunchFlow(defaults: suite)
        XCTAssertEqual(relaunched.initialAction(musicSourceNeeded: true), .none)
    }

    func testMusicSourceNotShownWhenNotNeeded() {
        LaunchFlow(defaults: suite).onboardingDidAppear()
        XCTAssertEqual(LaunchFlow(defaults: suite).initialAction(musicSourceNeeded: false), .none)
    }

    func testOnboardingTakesPrecedenceOverMusicSource() {
        XCTAssertEqual(LaunchFlow(defaults: suite).initialAction(musicSourceNeeded: true), .onboarding)
    }

    func testMusicSourceNeededTruthTable() {
        let controllers: [MediaControllerType] = [.nowPlaying, .appleMusic, .spotify, .youtubeMusic]
        for enabled in [true, false] {
            for deprecated in [true, false] {
                for controller in controllers {
                    let expected = enabled && deprecated && controller == .nowPlaying
                    XCTAssertEqual(
                        LaunchFlow.musicSourceNeeded(
                            mediaControlEnabled: enabled,
                            nowPlayingDeprecated: deprecated,
                            controller: controller
                        ),
                        expected,
                        "enabled=\(enabled) deprecated=\(deprecated) controller=\(controller)"
                    )
                }
            }
        }
    }
}
