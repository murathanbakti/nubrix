import XCTest
@testable import Nubrix

final class DockBadgeLabelTests: XCTestCase {
    func testPlainNumber() {
        let parsed = DockBadgeLabel.parse("3")
        XCTAssertEqual(parsed?.label, "3")
        XCTAssertEqual(parsed?.count, 3)
    }

    func testTrimsWhitespace() {
        let parsed = DockBadgeLabel.parse(" 12 ")
        XCTAssertEqual(parsed?.label, "12")
        XCTAssertEqual(parsed?.count, 12)
        XCTAssertEqual(DockBadgeLabel.parse("\n7\n")?.count, 7)
    }

    func testPlusSuffixKeepsLabelAndCount() {
        let parsed = DockBadgeLabel.parse("99+")
        XCTAssertEqual(parsed?.label, "99+")
        XCTAssertEqual(parsed?.count, 99)
    }

    func testDotAndTextLabelsHaveNoCount() {
        let dot = DockBadgeLabel.parse("•")
        XCTAssertEqual(dot?.label, "•")
        XCTAssertNil(dot?.count)
        let bang = DockBadgeLabel.parse("!")
        XCTAssertEqual(bang?.label, "!")
        XCTAssertNil(bang?.count)
        let word = DockBadgeLabel.parse("new")
        XCTAssertEqual(word?.label, "new")
        XCTAssertNil(word?.count)
    }

    func testEmptyInputsGiveNoBadge() {
        XCTAssertNil(DockBadgeLabel.parse(nil))
        XCTAssertNil(DockBadgeLabel.parse(""))
        XCTAssertNil(DockBadgeLabel.parse("   "))
        XCTAssertNil(DockBadgeLabel.parse("\n"))
    }

    func testZeroGivesNoBadge() {
        XCTAssertNil(DockBadgeLabel.parse("0"))
        XCTAssertNil(DockBadgeLabel.parse("000"))
        XCTAssertNil(DockBadgeLabel.parse(" 0 "))
    }

    func testLongLabelIsTruncated() {
        let parsed = DockBadgeLabel.parse("123456789012")
        XCTAssertEqual(parsed?.label, "12345678")
        XCTAssertEqual(parsed?.count, 123456789012)
        XCTAssertEqual(DockBadgeLabel.parse("abcdefghijkl")?.label, "abcdefgh")
    }

    func testOverflowingDigitsHaveNoCount() {
        let digits = String(repeating: "9", count: 30)
        let parsed = DockBadgeLabel.parse(digits)
        XCTAssertEqual(parsed?.label, "99999999")
        XCTAssertNil(parsed?.count)
    }

    func testMixedContentIsNotACount() {
        XCTAssertNil(DockBadgeLabel.parse("3 new")?.count)
        XCTAssertNil(DockBadgeLabel.parse("+5")?.count)
        XCTAssertNil(DockBadgeLabel.parse("1++")?.count)
    }
}
