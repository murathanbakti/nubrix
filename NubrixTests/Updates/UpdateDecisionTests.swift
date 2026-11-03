import XCTest
@testable import Nubrix

final class UpdateDecisionTests: XCTestCase {
    private let current = ReleaseVersion(major: 0, minor: 1, patch: 1)

    func testNewerIsAvailable() {
        let latest = ReleaseVersion(major: 0, minor: 2, patch: 0)
        XCTAssertEqual(UpdateDecision.evaluate(latest: latest, current: current, skipped: nil), .available(latest))
    }

    func testNewerPatchIsAvailable() {
        let latest = ReleaseVersion(major: 0, minor: 1, patch: 2)
        XCTAssertEqual(UpdateDecision.evaluate(latest: latest, current: current, skipped: nil), .available(latest))
    }

    func testEqualIsUpToDate() {
        XCTAssertEqual(UpdateDecision.evaluate(latest: current, current: current, skipped: nil), .upToDate)
    }

    func testOlderIsUpToDate() {
        let latest = ReleaseVersion(major: 0, minor: 1, patch: 0)
        XCTAssertEqual(UpdateDecision.evaluate(latest: latest, current: current, skipped: nil), .upToDate)
    }

    func testDowngradeIgnoresSkippedValue() {
        let latest = ReleaseVersion(major: 0, minor: 0, patch: 9)
        XCTAssertEqual(UpdateDecision.evaluate(latest: latest, current: current, skipped: latest.tag), .upToDate)
    }

    func testEqualIgnoresSkippedValue() {
        XCTAssertEqual(UpdateDecision.evaluate(latest: current, current: current, skipped: current.tag), .upToDate)
    }

    func testSkippedEqualToLatestIsSkipped() {
        let latest = ReleaseVersion(major: 0, minor: 2, patch: 0)
        XCTAssertEqual(UpdateDecision.evaluate(latest: latest, current: current, skipped: "v0.2.0"), .skipped(latest))
    }

    func testNewerThanSkippedIsAvailable() {
        let latest = ReleaseVersion(major: 0, minor: 3, patch: 0)
        XCTAssertEqual(UpdateDecision.evaluate(latest: latest, current: current, skipped: "v0.2.0"), .available(latest))
    }

    func testOlderSkippedValueDoesNotSuppress() {
        let latest = ReleaseVersion(major: 0, minor: 2, patch: 0)
        XCTAssertEqual(UpdateDecision.evaluate(latest: latest, current: current, skipped: "v0.1.5"), .available(latest))
    }

    func testGarbageSkippedValueDoesNotSuppress() {
        let latest = ReleaseVersion(major: 0, minor: 2, patch: 0)
        XCTAssertEqual(UpdateDecision.evaluate(latest: latest, current: current, skipped: "garbage"), .available(latest))
    }

    func testNumericComparisonAcrossTenBoundary() {
        let cur = ReleaseVersion(major: 0, minor: 9, patch: 9)
        let latest = ReleaseVersion(major: 0, minor: 10, patch: 0)
        XCTAssertEqual(UpdateDecision.evaluate(latest: latest, current: cur, skipped: nil), .available(latest))
    }
}
