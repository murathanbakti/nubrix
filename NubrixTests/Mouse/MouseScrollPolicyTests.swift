import XCTest
@testable import Nubrix

final class MouseScrollPolicyTests: XCTestCase {
    func testShouldReverseTable() {
        XCTAssertFalse(MouseScrollPolicy.shouldReverse(mode: .off, mouseConnected: false))
        XCTAssertFalse(MouseScrollPolicy.shouldReverse(mode: .off, mouseConnected: true))
        XCTAssertFalse(MouseScrollPolicy.shouldReverse(mode: .automatic, mouseConnected: false))
        XCTAssertTrue(MouseScrollPolicy.shouldReverse(mode: .automatic, mouseConnected: true))
        XCTAssertTrue(MouseScrollPolicy.shouldReverse(mode: .always, mouseConnected: false))
        XCTAssertTrue(MouseScrollPolicy.shouldReverse(mode: .always, mouseConnected: true))
    }

    func testStatusTable() {
        func status(_ mode: MouseScrollMode, mouse: Bool, granted: Bool, running: Bool) -> MouseScrollStatus {
            MouseScrollPolicy.status(mode: mode, mouseConnected: mouse, accessibilityGranted: granted, tapRunning: running)
        }
        XCTAssertEqual(status(.off, mouse: true, granted: true, running: true), .off)
        XCTAssertEqual(status(.automatic, mouse: true, granted: false, running: false), .needsAccessibility)
        XCTAssertEqual(status(.always, mouse: false, granted: false, running: false), .needsAccessibility)
        XCTAssertEqual(status(.automatic, mouse: false, granted: true, running: false), .waitingForMouse)
        XCTAssertEqual(status(.automatic, mouse: true, granted: true, running: true), .reversing)
        XCTAssertEqual(status(.automatic, mouse: true, granted: true, running: false), .tapFailed)
        XCTAssertEqual(status(.always, mouse: false, granted: true, running: true), .reversing)
        XCTAssertEqual(status(.always, mouse: false, granted: true, running: false), .tapFailed)
    }

    func testDirectionNames() {
        XCTAssertEqual(MouseScrollDirection.name(natural: true, reversed: false), "Natural")
        XCTAssertEqual(MouseScrollDirection.name(natural: true, reversed: true), "Standard")
        XCTAssertEqual(MouseScrollDirection.name(natural: false, reversed: false), "Standard")
        XCTAssertEqual(MouseScrollDirection.name(natural: false, reversed: true), "Natural")
    }

    func testStatusTitlesAreDistinct() {
        let all: [MouseScrollStatus] = [.off, .needsAccessibility, .waitingForMouse, .reversing, .tapFailed]
        let titles = all.map(\.title)
        XCTAssertTrue(titles.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(titles).count, titles.count)
    }

    func testModeTitles() {
        XCTAssertEqual(MouseScrollMode.allCases.map(\.title), ["Off", "When a mouse is connected", "Always"])
    }

    func testIsNatural() {
        XCTAssertTrue(NaturalScrolling.isNatural(nil))
        XCTAssertFalse(NaturalScrolling.isNatural(NSNumber(value: 0)))
        XCTAssertTrue(NaturalScrolling.isNatural(NSNumber(value: 1)))
        XCTAssertTrue(NaturalScrolling.isNatural(true))
        XCTAssertFalse(NaturalScrolling.isNatural(false))
        XCTAssertTrue(NaturalScrolling.isNatural("garbage"))
    }
}
