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
        XCTAssertEqual(first.initialAction(), .onboarding)
        first.onboardingDidAppear()
        let relaunched = LaunchFlow(defaults: suite)
        XCTAssertEqual(relaunched.initialAction(), .none)
    }

    func testOnboardingRepeatsUntilItAppears() {
        XCTAssertEqual(LaunchFlow(defaults: suite).initialAction(), .onboarding)
        XCTAssertEqual(LaunchFlow(defaults: suite).initialAction(), .onboarding)
    }
}
