import XCTest
@testable import Nubrix

final class UpdateInfoPlistTests: XCTestCase {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    func testFeedAndSecurityKeysAreExact() {
        XCTAssertEqual(info["SUFeedURL"] as? String, "https://github.com/murathanbakti/nubrix/releases/latest/download/appcast.xml")
        for key in ["SUEnableInstallerLauncherService", "SUVerifyUpdateBeforeExtraction", "SURequireSignedFeed"] {
            XCTAssertEqual(info[key] as? Bool, true, key)
        }
        for key in ["SUEnableAutomaticChecks", "SUAutomaticallyUpdate", "SUEnableSystemProfiling", "SUShowReleaseNotes"] {
            XCTAssertEqual(info[key] as? Bool, false, key)
        }
    }

    func testPublicKeyIsEmptyUntilTheOwnerSetsItOrAValidKey() throws {
        let key = try XCTUnwrap(info["SUPublicEDKey"] as? String)
        if !key.isEmpty {
            XCTAssertEqual(Data(base64Encoded: key)?.count, 32)
        }
    }

    func testKeysThatMustStayUnsetAreAbsent() {
        for key in ["SUEnableDownloaderService", "SUAllowsAutomaticUpdates", "SUScheduledCheckInterval", "SUSignedFeedFailureExpirationInterval"] {
            XCTAssertNil(info[key], key)
        }
    }
}
