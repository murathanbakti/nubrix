import AppKit
import XCTest
@testable import Nubrix

final class ClipboardPolicyTests: XCTestCase {
    func testAutomaticReadPolicy() throws {
        guard #available(macOS 15.4, *) else {
            throw XCTSkip("NSPasteboard.accessBehavior needs macOS 15.4")
        }
        XCTAssertFalse(ClipboardReadPolicy.automaticRead(.ask))
        XCTAssertFalse(ClipboardReadPolicy.automaticRead(.alwaysDeny))
        XCTAssertTrue(ClipboardReadPolicy.automaticRead(.default))
        XCTAssertTrue(ClipboardReadPolicy.automaticRead(.alwaysAllow))
    }
}
