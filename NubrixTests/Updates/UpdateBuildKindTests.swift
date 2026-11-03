import XCTest
@testable import Nubrix

final class UpdateBuildKindTests: XCTestCase {
    private let key = Data(repeating: 7, count: 32).base64EncodedString()

    private var goodInfo: [String: Any] {
        [
            "SUFeedURL": UpdateBuildKind.feedURL,
            "SUPublicEDKey": key,
            "SUEnableInstallerLauncherService": true,
            "SUVerifyUpdateBeforeExtraction": true,
            "SURequireSignedFeed": true,
        ]
    }

    private let goodSigning = AppSigningFacts(satisfiesReleaseRequirement: true, hasSecureTimestamp: true, teamIdentifier: "399MAAJ7QT")

    private func resolve(debug: Bool = false, bundle: String? = "dev.nubrix.app", signing: AppSigningFacts?? = .some(nil), info: [String: Any]? = nil) -> UpdateBuildKind {
        let facts: AppSigningFacts?
        switch signing {
        case .some(.some(let value)): facts = value
        case .some(.none): facts = goodSigning
        case .none: facts = nil
        }
        return UpdateBuildKind.resolve(isDebugBuild: debug, bundleIdentifier: bundle, signing: facts, info: info ?? goodInfo)
    }

    func testEverythingInOrderIsAReleaseThatMayUpdate() {
        let kind = resolve()
        XCTAssertEqual(kind, .developerIDRelease)
        XCTAssertTrue(kind.updatesEnabled)
        XCTAssertNil(kind.message)
        XCTAssertNil(kind.sourceCommand)
    }

    func testDebugFlagWinsOverAGoodRelease() {
        XCTAssertEqual(resolve(debug: true), .debugBuild)
    }

    func testOtherBundleIdentifiersAreSourceBuilds() {
        XCTAssertEqual(resolve(bundle: "dev.nubrix.app.debug"), .sourceBuild)
        XCTAssertEqual(resolve(bundle: nil), .sourceBuild)
    }

    func testMissingSigningFactsAreASourceBuild() {
        XCTAssertEqual(resolve(signing: .none), .sourceBuild)
    }

    func testRequirementMismatchIsASourceBuild() {
        let facts = AppSigningFacts(satisfiesReleaseRequirement: false, hasSecureTimestamp: true, teamIdentifier: "399MAAJ7QT")
        XCTAssertEqual(resolve(signing: .some(facts)), .sourceBuild)
    }

    func testDeveloperIDWithoutSecureTimestampIsASourceBuild() {
        let facts = AppSigningFacts(satisfiesReleaseRequirement: true, hasSecureTimestamp: false, teamIdentifier: "399MAAJ7QT")
        XCTAssertEqual(resolve(signing: .some(facts)), .sourceBuild)
    }

    func testWrongTeamIsASourceBuild() {
        let facts = AppSigningFacts(satisfiesReleaseRequirement: true, hasSecureTimestamp: true, teamIdentifier: "ABCDE12345")
        XCTAssertEqual(resolve(signing: .some(facts)), .sourceBuild)
        let none = AppSigningFacts(satisfiesReleaseRequirement: true, hasSecureTimestamp: true, teamIdentifier: nil)
        XCTAssertEqual(resolve(signing: .some(none)), .sourceBuild)
    }

    func testWrongOrInsecureFeedMeansUnavailable() {
        var info = goodInfo
        info["SUFeedURL"] = "http://github.com/murathanbakti/nubrix/releases/latest/download/appcast.xml"
        XCTAssertEqual(resolve(info: info), .unavailable)
        info["SUFeedURL"] = "https://example.com/appcast.xml"
        XCTAssertEqual(resolve(info: info), .unavailable)
        info.removeValue(forKey: "SUFeedURL")
        XCTAssertEqual(resolve(info: info), .unavailable)
    }

    func testEmptyMissingOrMalformedPublicKeyMeansUnavailable() {
        for value: Any? in [nil, "", "not base64!", Data(repeating: 1, count: 16).base64EncodedString(), Data(repeating: 1, count: 33).base64EncodedString(), 42] {
            var info = goodInfo
            info["SUPublicEDKey"] = value
            let kind = resolve(info: info)
            XCTAssertEqual(kind, .unavailable, "key \(String(describing: value))")
            XCTAssertFalse(kind.updatesEnabled)
        }
    }

    func testEachSecurityKeyMustBeTrue() {
        for name in UpdateBuildKind.requiredTrueKeys {
            var info = goodInfo
            info[name] = false
            XCTAssertEqual(resolve(info: info), .unavailable, "\(name) false")
            info.removeValue(forKey: name)
            XCTAssertEqual(resolve(info: info), .unavailable, "\(name) missing")
        }
    }

    func testOnlyTheReleaseKindUpdates() {
        XCTAssertTrue(UpdateBuildKind.developerIDRelease.updatesEnabled)
        for kind in [UpdateBuildKind.sourceBuild, .debugBuild, .unavailable] {
            XCTAssertFalse(kind.updatesEnabled)
        }
    }

    func testMessagesPerKind() {
        XCTAssertNil(UpdateBuildKind.developerIDRelease.message)
        XCTAssertEqual(UpdateBuildKind.debugBuild.message, "Debug build: updates are off.")
        XCTAssertEqual(UpdateBuildKind.unavailable.message, "Updates are not available in this build.")
        XCTAssertTrue(UpdateBuildKind.sourceBuild.message?.hasPrefix("Built from source") == true)
        XCTAssertEqual(UpdateBuildKind.sourceBuild.sourceCommand, "git pull && scripts/install-local.sh")
        XCTAssertNil(UpdateBuildKind.debugBuild.sourceCommand)
        XCTAssertNil(UpdateBuildKind.unavailable.sourceCommand)
    }

    func testThisTestHostIsADebugBuild() {
        XCTAssertEqual(UpdateBuildKind.current, .debugBuild)
    }
}
