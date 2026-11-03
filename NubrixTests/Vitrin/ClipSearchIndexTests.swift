import XCTest
@testable import Nubrix

final class ClipSearchIndexTests: XCTestCase {
    func testAllTokensMustMatch() {
        let index = ClipSearchIndex()
        index.insert(id: 1, used: 1, text: "alpha beta gamma")
        index.insert(id: 2, used: 2, text: "alpha delta")
        index.insert(id: 3, used: 3, text: "beta alpha")
        XCTAssertEqual(index.search("alpha beta", limit: 10), [3, 1])
        XCTAssertEqual(index.search("alpha", limit: 10), [3, 2, 1])
        XCTAssertEqual(index.search("alpha beta delta", limit: 10), [])
        XCTAssertEqual(index.search("  alpha \t\n beta ", limit: 10), [3, 1])
    }

    func testCaseFolding() {
        let index = ClipSearchIndex()
        index.insert(id: 1, used: 1, text: "Hello World")
        XCTAssertEqual(index.search("hello", limit: 5), [1])
        XCTAssertEqual(index.search("WORLD", limit: 5), [1])
    }

    func testDiacriticFolding() {
        let index = ClipSearchIndex()
        index.insert(id: 1, used: 1, text: "cay listesi")
        index.insert(id: 2, used: 2, text: "Çay saati")
        index.insert(id: 3, used: 3, text: "İstanbul")
        index.insert(id: 4, used: 4, text: "istanbul")
        XCTAssertEqual(index.search("Çay", limit: 10), [2, 1])
        XCTAssertEqual(index.search("cay", limit: 10), [2, 1])
        XCTAssertEqual(index.search("istanbul", limit: 10), [4, 3])
        XCTAssertEqual(index.search("İstanbul", limit: 10), [4, 3])
        XCTAssertEqual(index.search("cafe", limit: 10), [])
        index.insert(id: 5, used: 5, text: "Café")
        XCTAssertEqual(index.search("cafe", limit: 10), [5])
        XCTAssertEqual(index.search("café", limit: 10), [5])
    }

    func testSubstringSemantics() {
        let index = ClipSearchIndex()
        index.insert(id: 1, used: 1, text: "You are invited: invitation #7")
        index.insert(id: 2, used: 2, text: "nothing here")
        XCTAssertEqual(index.search("vit", limit: 10), [1])
        XCTAssertEqual(index.search("ation #7", limit: 10), [1])
        XCTAssertEqual(index.search("ation #8", limit: 10), [])
        XCTAssertEqual(index.search("ation", limit: 10), [1])
    }

    func testOrderUsedDescendingThenIDDescending() {
        let index = ClipSearchIndex()
        index.insert(id: 1, used: 100, text: "match")
        index.insert(id: 2, used: 300, text: "match")
        index.insert(id: 3, used: 200, text: "match")
        index.insert(id: 4, used: 300, text: "match")
        index.insert(id: 5, used: 100, text: "match")
        XCTAssertEqual(index.search("match", limit: 10), [4, 2, 3, 5, 1])
    }

    func testLimit() {
        let index = ClipSearchIndex()
        for id in 1...20 {
            index.insert(id: Int64(id), used: Double(id), text: "item \(id)")
        }
        XCTAssertEqual(index.search("item", limit: 3), [20, 19, 18])
        XCTAssertEqual(index.search("item", limit: 100).count, 20)
        XCTAssertEqual(index.search("item", limit: 0), [])
    }

    func testRemove() {
        let index = ClipSearchIndex()
        index.insert(id: 1, used: 1, text: "keep me")
        index.insert(id: 2, used: 2, text: "drop me")
        XCTAssertEqual(index.count, 2)
        index.remove(id: 2)
        XCTAssertEqual(index.count, 1)
        XCTAssertEqual(index.search("me", limit: 10), [1])
        index.remove(id: 99)
        XCTAssertEqual(index.count, 1)
    }

    func testTouchReorders() {
        let index = ClipSearchIndex()
        index.insert(id: 1, used: 10, text: "note")
        index.insert(id: 2, used: 20, text: "note")
        XCTAssertEqual(index.search("note", limit: 10), [2, 1])
        index.touch(id: 1, used: 30)
        XCTAssertEqual(index.search("note", limit: 10), [1, 2])
        index.touch(id: 404, used: 99)
        XCTAssertEqual(index.count, 2)
    }

    func testInsertSameIDReplacesText() {
        let index = ClipSearchIndex()
        index.insert(id: 1, used: 1, text: "old words")
        index.insert(id: 1, used: 2, text: "new words")
        XCTAssertEqual(index.count, 1)
        XCTAssertEqual(index.search("old", limit: 10), [])
        XCTAssertEqual(index.search("new", limit: 10), [1])
    }

    func testEmptyAndWhitespaceQueriesReturnNothing() {
        let index = ClipSearchIndex()
        index.insert(id: 1, used: 1, text: "anything")
        XCTAssertEqual(index.search("", limit: 10), [])
        XCTAssertEqual(index.search("   \n\t ", limit: 10), [])
    }

    func testTextPastMaxBytesIsNotFound() {
        let index = ClipSearchIndex()
        let padding = String(repeating: "a", count: ClipSearchIndex.maxBytesPerItem)
        index.insert(id: 1, used: 1, text: padding + " needle")
        index.insert(id: 2, used: 2, text: "needle " + padding)
        XCTAssertEqual(index.search("needle", limit: 10), [2])
    }

    func testFoldCutsAtMaxBytes() {
        let folded = ClipSearchIndex.fold(String(repeating: "x", count: ClipSearchIndex.maxBytesPerItem + 500))
        XCTAssertEqual(folded.count, ClipSearchIndex.maxBytesPerItem)
        XCTAssertEqual(ClipSearchIndex.fold("ÇAY"), Array("cay".utf8))
    }

    func testTokenLongerThanTextDoesNotMatch() {
        let index = ClipSearchIndex()
        index.insert(id: 1, used: 1, text: "ab")
        XCTAssertEqual(index.search("abcdef", limit: 10), [])
    }
}
