import XCTest
@testable import Nubrix

final class UpdateScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    private func due(autoCheck: Bool?, lastSuccess: Date? = nil, lastAttempt: Date? = nil) -> Bool {
        UpdateSchedule.isDue(autoCheck: autoCheck, lastSuccess: lastSuccess, lastAttempt: lastAttempt, now: now)
    }

    func testNilAutoCheckIsNeverDue() {
        XCTAssertFalse(due(autoCheck: nil))
        XCTAssertFalse(due(autoCheck: nil, lastSuccess: ago(10 * 86_400)))
    }

    func testFalseAutoCheckIsNeverDue() {
        XCTAssertFalse(due(autoCheck: false))
        XCTAssertFalse(due(autoCheck: false, lastSuccess: ago(10 * 86_400)))
    }

    func testOnAndNeverCheckedIsDue() {
        XCTAssertTrue(due(autoCheck: true))
    }

    func testOnAndOneHourAgoIsNotDue() {
        XCTAssertFalse(due(autoCheck: true, lastSuccess: ago(3_600)))
    }

    func testOnAnd25HoursAgoIsDue() {
        XCTAssertTrue(due(autoCheck: true, lastSuccess: ago(25 * 3_600)))
    }

    func testExactlyOneIntervalIsDue() {
        XCTAssertTrue(due(autoCheck: true, lastSuccess: ago(86_400)))
    }

    func testJustUnderOneIntervalIsNotDue() {
        XCTAssertFalse(due(autoCheck: true, lastSuccess: ago(86_399)))
    }

    func testRecentFailedAttemptIsNotDue() {
        XCTAssertFalse(due(autoCheck: true, lastSuccess: nil, lastAttempt: ago(600)))
        XCTAssertFalse(due(autoCheck: true, lastSuccess: ago(30 * 3_600), lastAttempt: ago(600)))
    }

    func testOldAttemptNoLongerBlocks() {
        XCTAssertTrue(due(autoCheck: true, lastSuccess: ago(30 * 3_600), lastAttempt: ago(3_601)))
        XCTAssertTrue(due(autoCheck: true, lastSuccess: nil, lastAttempt: ago(3_600)))
    }

    func testAttemptJustInsideRetryWindowBlocks() {
        XCTAssertFalse(due(autoCheck: true, lastSuccess: nil, lastAttempt: ago(3_599)))
    }

    func testAttemptInTheFutureDoesNotBlock() {
        XCTAssertTrue(due(autoCheck: true, lastSuccess: nil, lastAttempt: now.addingTimeInterval(120)))
    }

    func testClockMovedBackIsDue() {
        XCTAssertTrue(due(autoCheck: true, lastSuccess: now.addingTimeInterval(3_600)))
        XCTAssertTrue(due(autoCheck: true, lastSuccess: now.addingTimeInterval(301)))
    }

    func testSmallFutureSkewIsNotDue() {
        XCTAssertFalse(due(autoCheck: true, lastSuccess: now.addingTimeInterval(299)))
        XCTAssertFalse(due(autoCheck: true, lastSuccess: now.addingTimeInterval(300)))
    }

    func testAutoCheckOffWinsOverClockSkew() {
        XCTAssertFalse(due(autoCheck: false, lastSuccess: now.addingTimeInterval(3_600)))
    }

    func testCustomIntervals() {
        XCTAssertTrue(UpdateSchedule.isDue(autoCheck: true, lastSuccess: ago(120), lastAttempt: nil, now: now, interval: 60, retryAfterFailure: 10))
        XCTAssertFalse(UpdateSchedule.isDue(autoCheck: true, lastSuccess: ago(120), lastAttempt: ago(5), now: now, interval: 60, retryAfterFailure: 10))
    }
}
