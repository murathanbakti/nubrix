import CoreGraphics
import XCTest
@testable import Nubrix

final class ScrollReversalTests: XCTestCase {
    private func wheelEvent(units: CGScrollEventUnit = .line, _ w1: Int32, _ w2: Int32) throws -> CGEvent {
        try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 2, wheel1: w1, wheel2: w2, wheel3: 0))
    }

    private struct Fields: Equatable {
        var delta1, delta2, point1, point2: Int64
        var fixed1, fixed2: Double

        init(_ event: CGEvent) {
            delta1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            delta2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            point1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            point2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            fixed1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            fixed2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        }
    }

    func testLineWheelEventIsFullyNegated() throws {
        let event = try wheelEvent(3, -1)
        let before = Fields(event)
        XCTAssertTrue(ScrollReversal.apply(to: event, reverseHorizontal: true))
        let after = Fields(event)
        XCTAssertEqual(after.delta1, -before.delta1)
        XCTAssertEqual(after.delta2, -before.delta2)
        XCTAssertEqual(after.point1, -before.point1)
        XCTAssertEqual(after.point2, -before.point2)
        XCTAssertEqual(after.fixed1, -before.fixed1)
        XCTAssertEqual(after.fixed2, -before.fixed2)
        XCTAssertNotEqual(before.delta1, 0)
    }

    func testHorizontalAxisStaysWhenNotReversed() throws {
        let event = try wheelEvent(3, -1)
        let before = Fields(event)
        XCTAssertTrue(ScrollReversal.apply(to: event, reverseHorizontal: false))
        let after = Fields(event)
        XCTAssertEqual(after.delta1, -before.delta1)
        XCTAssertEqual(after.point1, -before.point1)
        XCTAssertEqual(after.fixed1, -before.fixed1)
        XCTAssertEqual(after.delta2, before.delta2)
        XCTAssertEqual(after.point2, before.point2)
        XCTAssertEqual(after.fixed2, before.fixed2)
    }

    func testSmoothScrollingMouseWithoutPhaseIsFlipped() throws {
        let event = try wheelEvent(units: .pixel, 12, 4)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventIsContinuous), 1)
        let before = Fields(event)
        XCTAssertTrue(ScrollReversal.apply(to: event, reverseHorizontal: true))
        let after = Fields(event)
        XCTAssertEqual(after.point1, -before.point1)
        XCTAssertEqual(after.point2, -before.point2)
    }

    func testScrollPhaseEventIsUntouched() throws {
        let event = try wheelEvent(units: .pixel, 12, 4)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
        let before = Fields(event)
        XCTAssertFalse(ScrollReversal.apply(to: event, reverseHorizontal: true))
        XCTAssertEqual(Fields(event), before)
    }

    func testMomentumPhaseEventIsUntouched() throws {
        let event = try wheelEvent(units: .pixel, 12, 4)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2)
        let before = Fields(event)
        XCTAssertFalse(ScrollReversal.apply(to: event, reverseHorizontal: true))
        XCTAssertEqual(Fields(event), before)
    }

    func testNonScrollEventIsIgnored() throws {
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: .zero, mouseButton: .left))
        XCTAssertFalse(ScrollReversal.apply(to: event, reverseHorizontal: true))
    }

    func testApplyingTwiceRestoresTheOriginal() throws {
        let event = try wheelEvent(5, -2)
        let before = Fields(event)
        ScrollReversal.apply(to: event, reverseHorizontal: true)
        ScrollReversal.apply(to: event, reverseHorizontal: true)
        XCTAssertEqual(Fields(event), before)
    }

    func testZeroDeltasStayZero() throws {
        let event = try wheelEvent(0, 0)
        ScrollReversal.apply(to: event, reverseHorizontal: true)
        let after = Fields(event)
        XCTAssertEqual(after.delta1, 0)
        XCTAssertEqual(after.delta2, 0)
        XCTAssertEqual(after.point1, 0)
        XCTAssertEqual(after.point2, 0)
        XCTAssertEqual(after.fixed1, 0)
        XCTAssertEqual(after.fixed2, 0)
    }
}

final class ScrollEventClassifierTests: XCTestCase {
    func testTable() {
        let cases: [(continuous: Int64, phase: Int64, momentum: Int64, expected: ScrollEventSource)] = [
            (0, 0, 0, .wheel),
            (1, 0, 0, .wheel),
            (1, 1, 0, .gesture),
            (1, 2, 0, .gesture),
            (1, 4, 0, .gesture),
            (1, 8, 0, .gesture),
            (1, 128, 0, .gesture),
            (1, 0, 1, .gesture),
            (1, 0, 2, .gesture),
            (1, 0, 3, .gesture),
            (0, 4, 0, .gesture),
            (1, 4, 2, .gesture)
        ]
        for c in cases {
            XCTAssertEqual(
                ScrollEventClassifier.source(isContinuous: c.continuous, scrollPhase: c.phase, momentumPhase: c.momentum),
                c.expected, "\(c)"
            )
        }
    }

    func testClassifiesRealEvents() throws {
        let line = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 3, wheel2: 0, wheel3: 0))
        XCTAssertEqual(ScrollEventClassifier.source(of: line), .wheel)
        line.setIntegerValueField(.scrollWheelEventScrollPhase, value: 128)
        XCTAssertEqual(ScrollEventClassifier.source(of: line), .gesture)
    }
}
