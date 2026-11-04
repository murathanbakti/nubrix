import Defaults
import Foundation
import XCTest
@testable import Nubrix

@MainActor
final class SystemNotificationGroupingTests: XCTestCase {
    private func rec(_ id: Int64, _ bundle: String, title: String = "", thread: String = "") -> SystemNotificationRecord {
        SystemNotificationRecord(recID: id, bundleID: bundle, appName: bundle, title: title, subtitle: "", body: "b",
                                 thread: thread, date: Date(timeIntervalSince1970: Double(1000 - id)))
    }

    // newest first, as the store keeps them
    private var sample: [SystemNotificationRecord] {
        [rec(1, "a", thread: "x"), rec(2, "b", thread: "y"), rec(3, "a", thread: "x"), rec(4, "a", thread: "z"), rec(5, "b", thread: "y")]
    }

    func test_conversationGroupsByThreadAndKeepsNewestOrder() {
        let stacks = SystemNotificationStack.stacks(from: sample, grouping: .conversation)
        XCTAssertEqual(stacks.map(\.records.count), [2, 2, 1])
        XCTAssertEqual(stacks.map { $0.records.first?.recID }, [1, 2, 4])
        XCTAssertTrue(stacks.allSatisfy { !$0.isAppGroup })
    }

    func test_appGroupsOneStackPerBundle() {
        let stacks = SystemNotificationStack.stacks(from: sample, grouping: .app)
        XCTAssertEqual(stacks.count, 2)
        XCTAssertEqual(stacks.map(\.bundleID), ["a", "b"])
        XCTAssertEqual(stacks.map(\.records.count), [3, 2])
        XCTAssertEqual(stacks[0].records.map(\.recID), [1, 3, 4])
        XCTAssertTrue(stacks.allSatisfy(\.isAppGroup))
        XCTAssertEqual(stacks[0].id, "app:a")
    }

    func test_offGivesEveryRecordItsOwnStack() {
        let stacks = SystemNotificationStack.stacks(from: sample, grouping: .off)
        XCTAssertEqual(stacks.count, 5)
        XCTAssertTrue(stacks.allSatisfy { $0.records.count == 1 })
        XCTAssertEqual(stacks.map { $0.records[0].recID }, [1, 2, 3, 4, 5])
        XCTAssertEqual(Set(stacks.map(\.id)).count, 5)
    }

    func test_emptyInputGivesNoStacks() {
        for mode in SystemNotificationGrouping.allCases {
            XCTAssertTrue(SystemNotificationStack.stacks(from: [], grouping: mode).isEmpty)
        }
    }

    func test_recordIDsCoverTheWholeStack() {
        let stacks = SystemNotificationStack.stacks(from: sample, grouping: .app)
        XCTAssertEqual(stacks[0].recordIDs, Set(stacks[0].records.map(\.id)))
    }

    func test_defaultsKeepTodaysBehaviour() {
        XCTAssertEqual(Defaults.Keys.systemNotificationGrouping.defaultValue, .conversation)
        XCTAssertEqual(Defaults.Keys.systemNotificationsCollapseGroups.defaultValue, true)
        XCTAssertEqual(Defaults.Keys.systemNotificationsShowBanner.defaultValue, true)
        XCTAssertEqual(SystemNotificationGrouping.allCases.map(\.title), ["By conversation", "By app", "Off"])
    }

    func test_cardGate() {
        XCTAssertTrue(SystemNotificationStore.cardAllowed(showBanner: true))
        XCTAssertFalse(SystemNotificationStore.cardAllowed(showBanner: false))
    }
}
