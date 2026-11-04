import XCTest
@testable import Nubrix

final class DefaultsMigrationTests: XCTestCase {
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

    /// Only what was written to this suite, not defaults registered elsewhere.
    private var written: [String: Any] { suite.persistentDomain(forName: suiteName) ?? [:] }

    func testNewInstallWritesNothing() {
        DefaultsMigration.run(suite, domain: suiteName)
        for key in DefaultsMigration.previousDefaults.keys {
            XCTAssertNil(written[key], key)
        }
    }

    func testExistingInstallGetsPreviousDefaults() {
        suite.set(false, forKey: "firstLaunch")
        DefaultsMigration.run(suite, domain: suiteName)
        XCTAssertEqual(written["claudeEnabled"] as? Bool, true)
        XCTAssertEqual(written["enableSneakPeek"] as? Bool, false)
        XCTAssertEqual(written["systemNotificationStyle"] as? String, "inline")
        for key in DefaultsMigration.previousDefaults.keys {
            XCTAssertNotNil(written[key], key)
        }
    }

    func testValueTheUserSetIsKept() {
        suite.set(false, forKey: "firstLaunch")
        suite.set(false, forKey: "claudeEnabled")
        suite.set("dropDown", forKey: "systemNotificationStyle")
        DefaultsMigration.run(suite, domain: suiteName)
        XCTAssertEqual(suite.bool(forKey: "claudeEnabled"), false)
        XCTAssertEqual(suite.string(forKey: "systemNotificationStyle"), "dropDown")
    }

    func testRunningTwiceChangesNothing() {
        suite.set(false, forKey: "firstLaunch")
        DefaultsMigration.run(suite, domain: suiteName)
        suite.set(false, forKey: "claudeEnabled")
        suite.set("dropDown", forKey: "systemNotificationStyle")
        DefaultsMigration.run(suite, domain: suiteName)
        XCTAssertEqual(suite.bool(forKey: "claudeEnabled"), false)
        XCTAssertEqual(suite.string(forKey: "systemNotificationStyle"), "dropDown")
    }
}
