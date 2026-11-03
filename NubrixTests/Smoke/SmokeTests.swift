import XCTest
@testable import Nubrix

final class SmokeTests: XCTestCase {
    func testHostedInsideNubrixApp() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "dev.nubrix.app.debug")
    }

    func testClipInsightDetectsJSON() {
        let insight = ClipInsightAnalyzer.analyze(#"{"b":1,"a":[true,null]}"#)
        XCTAssertEqual(insight?.kind, .json)
        XCTAssertEqual(insight?.actions.map(\.title), ["Copy pretty JSON", "Copy minified JSON"])
        XCTAssertEqual(insight?.actions.last?.output, #"{"a":[true,null],"b":1}"#)
    }

    func testClipInsightIgnoresPlainText() {
        XCTAssertNil(ClipInsightAnalyzer.analyze("hello there"))
        XCTAssertNil(ClipInsightAnalyzer.analyze("   "))
    }

    func testSecretGuardFlagsPrivateKey() {
        XCTAssertTrue(SecretGuard.looksLikeSecret("-----BEGIN RSA PRIVATE KEY-----", isURL: false))
        XCTAssertFalse(SecretGuard.looksLikeSecret("just a note", isURL: false))
    }
}
