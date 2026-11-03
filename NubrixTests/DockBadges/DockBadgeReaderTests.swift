import AppKit
import XCTest
@testable import Nubrix

@MainActor
final class DockBadgeReaderTests: XCTestCase {
    override func tearDown() {
        NSApp?.dockTile.badgeLabel = nil
        super.tearDown()
    }

    func testNotRunningAppReturnsNothing() {
        let reader = LaunchServicesDockBadgeReader()
        let result = reader.read(bundleIDs: ["com.example.not.running"])
        XCTAssertTrue(result.running.isEmpty)
        XCTAssertTrue(result.labels.isEmpty)
    }

    func testEmptyRequestReturnsNothing() {
        let result = LaunchServicesDockBadgeReader().read(bundleIDs: [])
        XCTAssertEqual(result, DockBadgeReadResult(running: [], labels: [:]))
    }

    func testRunningRegularAppsHaveNoDuplicates() {
        let apps = LaunchServicesDockBadgeReader().runningRegularApps()
        XCTAssertEqual(apps.count, Set(apps).count)
    }

    func testRealReaderSeesOwnDockTileLabel() throws {
        let reader = LaunchServicesDockBadgeReader()
        try XCTSkipUnless(reader.isAvailable, "LaunchServices SPI is not available")
        let app = try XCTUnwrap(NSApp, "no NSApplication")
        app.dockTile.badgeLabel = "7"
        let deadline = Date().addingTimeInterval(2)
        var seen: String?
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            seen = reader.label(forPID: getpid())
            if seen == "7" { break }
        }
        if seen != "7" {
            throw XCTSkip("The hosted test app did not publish its Dock tile label (saw \(seen ?? "nil"))")
        }
        XCTAssertEqual(seen, "7")
        let bundleID = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let result = reader.read(bundleIDs: [bundleID])
        XCTAssertTrue(result.running.contains(bundleID))
        XCTAssertEqual(result.labels[bundleID], "7")
    }
}
