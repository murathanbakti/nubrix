import XCTest
@testable import Nubrix

final class ReleaseVersionTests: XCTestCase {
    func testValidTags() {
        XCTAssertEqual(ReleaseVersion(tag: "v1.2.3"), ReleaseVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(ReleaseVersion(tag: "v0.0.0"), ReleaseVersion(major: 0, minor: 0, patch: 0))
        XCTAssertEqual(ReleaseVersion(tag: "v0.1.1"), ReleaseVersion(major: 0, minor: 1, patch: 1))
        XCTAssertEqual(ReleaseVersion(tag: "v10.20.30"), ReleaseVersion(major: 10, minor: 20, patch: 30))
        XCTAssertEqual(ReleaseVersion(tag: "v999999.999999.999999"), ReleaseVersion(major: 999_999, minor: 999_999, patch: 999_999))
    }

    func testRejectedTags() {
        let rejected = [
            "", "v", "1.2.3", "V1.2.3", "v1.2", "v1", "v1.2.3.4", "v1.2.3-beta.1", "v1.2.3+build",
            "v01.2.3", "v1.02.3", "v1.2.03", " v1.2.3", "v1.2.3 ", "v1.2.3\n", "\nv1.2.3",
            "v\u{FF11}.2.3", "v1.\u{FF12}.3", "v1.2.\u{0663}",
            "v1000000.0.0", "v0.1000000.0", "v0.0.1000000", "v1..3", "v.1.2", "v1.2.", "v-1.2.3", "v+1.2.3", "v1.2.x"
        ]
        for tag in rejected {
            XCTAssertNil(ReleaseVersion(tag: tag), "expected rejection of \(tag.debugDescription)")
        }
    }

    func testBundleVersionAcceptsThreeComponents() {
        XCTAssertEqual(ReleaseVersion(bundleVersion: "1.2.3"), ReleaseVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(ReleaseVersion(bundleVersion: "0.1.1"), ReleaseVersion(major: 0, minor: 1, patch: 1))
    }

    func testBundleVersionAcceptsTwoComponentsAsPatchZero() {
        XCTAssertEqual(ReleaseVersion(bundleVersion: "1.2"), ReleaseVersion(major: 1, minor: 2, patch: 0))
        XCTAssertEqual(ReleaseVersion(bundleVersion: "0.9"), ReleaseVersion(major: 0, minor: 9, patch: 0))
    }

    func testBundleVersionRejectsGarbage() {
        let rejected = [
            "", "1", "v1.2.3", "1.2.3.4", "1.2.3-beta", "1.2.3+1", "abc", "1.x.3", "01.2.3", "1.2.03",
            " 1.2.3", "1.2.3 ", "1..3", "1.2.", ".1.2", "\u{FF11}.2.3", "1234567.0.0", "$(MARKETING_VERSION)"
        ]
        for version in rejected {
            XCTAssertNil(ReleaseVersion(bundleVersion: version), "expected rejection of \(version.debugDescription)")
        }
    }

    func testTagAndDescription() {
        let version = ReleaseVersion(major: 1, minor: 2, patch: 3)
        XCTAssertEqual(version.tag, "v1.2.3")
        XCTAssertEqual(version.description, "1.2.3")
        XCTAssertEqual("\(version)", "1.2.3")
        XCTAssertEqual(ReleaseVersion(tag: version.tag), version)
    }

    func testOrderingIsNumeric() {
        XCTAssertGreaterThan(ReleaseVersion(major: 0, minor: 10, patch: 0), ReleaseVersion(major: 0, minor: 9, patch: 9))
        XCTAssertGreaterThan(ReleaseVersion(major: 1, minor: 0, patch: 0), ReleaseVersion(major: 0, minor: 99, patch: 99))
        XCTAssertGreaterThan(ReleaseVersion(major: 0, minor: 1, patch: 10), ReleaseVersion(major: 0, minor: 1, patch: 9))
        XCTAssertLessThan(ReleaseVersion(major: 0, minor: 1, patch: 1), ReleaseVersion(major: 0, minor: 1, patch: 2))
        XCTAssertLessThan(ReleaseVersion(major: 0, minor: 2, patch: 0), ReleaseVersion(major: 1, minor: 0, patch: 0))
    }

    func testEqualityAndHashing() {
        let a = ReleaseVersion(major: 1, minor: 2, patch: 3)
        let b = ReleaseVersion(tag: "v1.2.3")
        XCTAssertEqual(a, b)
        XCTAssertFalse(a < a)
        XCTAssertTrue(a <= a)
        XCTAssertTrue(a >= a)
        XCTAssertEqual(Set([a, b!]).count, 1)
        XCTAssertNotEqual(a, ReleaseVersion(major: 1, minor: 2, patch: 4))
    }

    func testTwoComponentBundleVersionEqualsExplicitPatchZero() {
        XCTAssertEqual(ReleaseVersion(bundleVersion: "1.2"), ReleaseVersion(bundleVersion: "1.2.0"))
    }
}
