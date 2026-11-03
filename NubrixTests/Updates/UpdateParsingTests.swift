import XCTest
@testable import Nubrix

final class UpdateParsingTests: XCTestCase {
    private func parse(_ json: String) throws -> ReleaseVersion {
        try UpdateParsing.latestVersion(from: Data(json.utf8))
    }

    private func assertFailure(_ expected: UpdateFailure, _ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try UpdateParsing.latestVersion(from: data), file: file, line: line) { error in
            XCTAssertEqual(error as? UpdateFailure, expected, file: file, line: line)
        }
    }

    private func assertFailure(_ expected: UpdateFailure, _ json: String, file: StaticString = #filePath, line: UInt = #line) {
        assertFailure(expected, Data(json.utf8), file: file, line: line)
    }

    func testMinimalJSON() throws {
        XCTAssertEqual(try parse(#"{"tag_name":"v0.2.0"}"#), ReleaseVersion(major: 0, minor: 2, patch: 0))
    }

    func testExplicitFalseFlagsAreAccepted() throws {
        XCTAssertEqual(try parse(#"{"tag_name":"v1.0.0","draft":false,"prerelease":false}"#), ReleaseVersion(major: 1, minor: 0, patch: 0))
    }

    func testNullFlagsAreAccepted() throws {
        XCTAssertEqual(try parse(#"{"tag_name":"v1.0.0","draft":null,"prerelease":null}"#), ReleaseVersion(major: 1, minor: 0, patch: 0))
    }

    func testExtraFieldsAreIgnored() throws {
        let json = #"""
        {"url":"https://evil.example/x","id":1,"name":"Big release","body":"notes","html_url":"https://evil.example/y",
         "author":{"login":"x","id":2},"assets":[{"name":"a.zip","browser_download_url":"https://evil.example/a.zip"}],
         "tag_name":"v3.4.5","draft":false,"prerelease":false,"published_at":"2026-11-03T10:00:00Z"}
        """#
        XCTAssertEqual(try parse(json), ReleaseVersion(major: 3, minor: 4, patch: 5))
    }

    func testDraftIsNotEligible() {
        assertFailure(.notEligible, #"{"tag_name":"v1.0.0","draft":true}"#)
    }

    func testPrereleaseIsNotEligible() {
        assertFailure(.notEligible, #"{"tag_name":"v1.0.0","prerelease":true}"#)
    }

    func testDraftAndPrereleaseTogetherAreNotEligible() {
        assertFailure(.notEligible, #"{"tag_name":"v1.0.0","draft":true,"prerelease":true}"#)
    }

    func testMissingTagNameIsMalformed() {
        assertFailure(.malformed, #"{"name":"v1.0.0"}"#)
    }

    func testNumericTagNameIsMalformed() {
        assertFailure(.malformed, #"{"tag_name":1}"#)
    }

    func testNullTagNameIsMalformed() {
        assertFailure(.malformed, #"{"tag_name":null}"#)
    }

    func testArrayRootIsMalformed() {
        assertFailure(.malformed, #"[{"tag_name":"v1.0.0"}]"#)
    }

    func testScalarRootIsMalformed() {
        assertFailure(.malformed, #""v1.0.0""#)
    }

    func testEmptyDataIsMalformed() {
        assertFailure(.malformed, Data())
    }

    func testGarbageIsMalformed() {
        assertFailure(.malformed, "not json at all")
    }

    func testWrongTypedFlagIsMalformed() {
        assertFailure(.malformed, #"{"tag_name":"v1.0.0","draft":"yes"}"#)
    }

    func testBodyOverOneMiBIsMalformed() {
        let padding = String(repeating: " ", count: UpdateParsing.maxBodyBytes)
        assertFailure(.malformed, #"{"tag_name":"v1.0.0"}"# + padding)
    }

    func testBodyExactlyOneMiBIsAccepted() throws {
        let base = #"{"tag_name":"v1.0.0"}"#
        let padding = String(repeating: " ", count: UpdateParsing.maxBodyBytes - base.utf8.count)
        let data = Data((base + padding).utf8)
        XCTAssertEqual(data.count, 1_048_576)
        XCTAssertEqual(try UpdateParsing.latestVersion(from: data), ReleaseVersion(major: 1, minor: 0, patch: 0))
    }

    func testPreReleaseTagStringIsInvalidTag() {
        assertFailure(.invalidTag, #"{"tag_name":"v1.2.3-beta.1"}"#)
    }

    func testTagWithoutVPrefixIsInvalidTag() {
        assertFailure(.invalidTag, #"{"tag_name":"1.2.3"}"#)
    }

    func testEmptyTagIsInvalidTag() {
        assertFailure(.invalidTag, #"{"tag_name":""}"#)
    }

    func testFailureMessagesAreNonEmpty() {
        let all: [UpdateFailure] = [.network, .http(500), .rateLimited, .notFound, .redirected, .malformed, .invalidTag, .notEligible, .unknownCurrentVersion]
        for failure in all { XCTAssertFalse(failure.message.isEmpty) }
        XCTAssertTrue(UpdateFailure.http(503).message.contains("503"))
    }
}
