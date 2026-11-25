import XCTest
@testable import Nubrix

final class FakeMouseMonitor: MouseDeviceMonitoring {
    var onChange: (([MouseDevice]) -> Void)?
    var scanResult: [MouseDevice] = []
    private(set) var isRunning = false
    private(set) var starts = 0
    private(set) var stops = 0

    func start() {
        guard !isRunning else { return }
        isRunning = true
        starts += 1
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stops += 1
    }

    func scan() -> [MouseDevice] { scanResult }
    func emit(_ mice: [MouseDevice]) { onChange?(mice) }
}

final class FakeScrollTap: ScrollTapping {
    var startResult = true
    private(set) var running = false
    private(set) var starts: [Bool] = []
    private(set) var updates: [Bool] = []
    private(set) var stops = 0

    var isRunning: Bool { running }

    func start(reverseHorizontal: Bool) -> Bool {
        starts.append(reverseHorizontal)
        running = startResult
        return startResult
    }

    func update(reverseHorizontal: Bool) { updates.append(reverseHorizontal) }

    func stop() {
        running = false
        stops += 1
    }
}

@MainActor
final class MouseScrollControllerTests: XCTestCase {
    private var monitor: FakeMouseMonitor!
    private var tap: FakeScrollTap!
    private var permissions: FakePermissionClient!
    private var settings = MouseScrollSettings(mode: .off, reverseHorizontal: true)
    private var natural = true
    private var written: [Set<String>] = []
    private var controller: MouseScrollController!
    private let usbMouse = MouseDevice(id: "1-1-1", name: "USB Optical Mouse", transport: "USB", vendorID: 1, productID: 1)

    override func setUp() {
        super.setUp()
        monitor = FakeMouseMonitor()
        tap = FakeScrollTap()
        permissions = FakePermissionClient(statuses: [.accessibility: .granted])
        settings = MouseScrollSettings(mode: .off, reverseHorizontal: true)
        natural = true
        controller = MouseScrollController(
            monitor: monitor, tap: tap, permissions: permissions,
            settings: { [unowned self] in settings },
            naturalScrolling: { [unowned self] in natural },
            writeIgnoredDevices: { [unowned self] in written.append($0) }
        )
    }

    func testOffDoesNothing() async {
        await controller.evaluate()
        XCTAssertFalse(monitor.isRunning)
        XCTAssertTrue(tap.starts.isEmpty)
        XCTAssertEqual(controller.status, .off)
        XCTAssertTrue(permissions.statusCalls.isEmpty)
        XCTAssertTrue(permissions.requests.isEmpty)
    }

    func testAutomaticWithoutMouseWaits() async {
        settings.mode = .automatic
        await controller.evaluate()
        XCTAssertTrue(monitor.isRunning)
        XCTAssertTrue(tap.starts.isEmpty)
        XCTAssertEqual(controller.status, .waitingForMouse)
    }

    func testMouseConnectingStartsTheTapAndDisconnectingStopsIt() async {
        settings = MouseScrollSettings(mode: .automatic, reverseHorizontal: false)
        await controller.evaluate()
        await controller.handleMiceChange([usbMouse])
        XCTAssertEqual(tap.starts, [false])
        XCTAssertEqual(controller.status, .reversing)
        XCTAssertEqual(controller.mice, [usbMouse])

        await controller.handleMiceChange([])
        XCTAssertEqual(tap.stops, 1)
        XCTAssertFalse(tap.isRunning)
        XCTAssertEqual(controller.status, .waitingForMouse)
    }

    func testAlwaysReversesWithoutAMouse() async {
        settings.mode = .always
        await controller.evaluate()
        XCTAssertEqual(tap.starts, [true])
        XCTAssertEqual(controller.status, .reversing)
    }

    func testWithoutAccessibilityNothingStartsAndNothingIsRequested() async {
        permissions.statuses[.accessibility] = .notDetermined
        settings.mode = .always
        await controller.evaluate()
        XCTAssertTrue(tap.starts.isEmpty)
        XCTAssertEqual(controller.status, .needsAccessibility)
        XCTAssertFalse(controller.accessibilityGranted)
        XCTAssertTrue(permissions.requests.isEmpty)
    }

    func testTapFailureIsReported() async {
        tap.startResult = false
        settings.mode = .always
        await controller.evaluate()
        XCTAssertEqual(controller.status, .tapFailed)
    }

    func testHorizontalChangeUpdatesInsteadOfRestarting() async {
        settings.mode = .always
        await controller.evaluate()
        settings.reverseHorizontal = false
        await controller.evaluate()
        XCTAssertEqual(tap.starts, [true])
        XCTAssertEqual(tap.updates, [false])
    }

    func testSwitchingOffStopsTapAndMonitor() async {
        settings.mode = .always
        await controller.evaluate()
        settings.mode = .off
        await controller.evaluate()
        XCTAssertEqual(tap.stops, 1)
        XCTAssertFalse(monitor.isRunning)
        XCTAssertEqual(monitor.stops, 1)
        XCTAssertEqual(controller.status, .off)
    }

    func testRequestAccessibilityAsksOnceThenReverses() async {
        permissions.statuses[.accessibility] = .notDetermined
        settings.mode = .always
        await controller.evaluate()
        XCTAssertEqual(controller.status, .needsAccessibility)

        permissions.statuses[.accessibility] = .granted
        await controller.requestAccessibility()
        XCTAssertEqual(permissions.requests, [.accessibility])
        XCTAssertEqual(controller.status, .reversing)
    }

    func testDirectionStrings() async {
        settings.mode = .always
        await controller.evaluate()
        XCTAssertEqual(controller.trackpadDirection, "Natural")
        XCTAssertEqual(controller.mouseWheelDirection, "Standard")

        natural = false
        await controller.evaluate()
        XCTAssertEqual(controller.trackpadDirection, "Standard")
        XCTAssertEqual(controller.mouseWheelDirection, "Natural")

        settings.mode = .off
        await controller.evaluate()
        XCTAssertEqual(controller.mouseWheelDirection, "Standard")
    }

    func testRefreshDevicesScansEvenWhenOff() {
        monitor.scanResult = [usbMouse]
        controller.refreshDevices()
        XCTAssertEqual(controller.mice, [usbMouse])
        XCTAssertFalse(monitor.isRunning)
    }

    func testMonitorCallbackReachesTheController() async {
        settings.mode = .automatic
        await controller.evaluate()
        monitor.emit([usbMouse])
        for _ in 0..<50 where controller.status != .reversing { await Task.yield() }
        XCTAssertEqual(controller.status, .reversing)
    }

    func testIgnoredDeviceDoesNotCountAndUnignoringReverses() async {
        settings = MouseScrollSettings(mode: .automatic, reverseHorizontal: true, ignoredDevices: [usbMouse.key])
        await controller.evaluate()
        await controller.handleMiceChange([usbMouse])
        XCTAssertEqual(controller.mice, [usbMouse])
        XCTAssertTrue(controller.countedMice.isEmpty)
        XCTAssertEqual(controller.status, .waitingForMouse)
        XCTAssertFalse(tap.isRunning)

        settings.ignoredDevices = []
        await controller.evaluate()
        XCTAssertEqual(controller.status, .reversing)
        XCTAssertTrue(tap.isRunning)
    }

    func testSetCountedWritesAndRemovesTheKey() {
        controller.setCounted(usbMouse, false)
        XCTAssertEqual(controller.ignoredDevices, [usbMouse.key])
        controller.setCounted(usbMouse, false)
        controller.setCounted(usbMouse, true)
        XCTAssertEqual(written, [[usbMouse.key], [usbMouse.key], []])
        XCTAssertTrue(controller.ignoredDevices.isEmpty)
    }

    func testModeDidChangeDoesNotAskWhenGranted() async {
        await controller.modeDidChange(to: .automatic)
        XCTAssertTrue(permissions.requests.isEmpty)
    }

    func testModeDidChangeAsksOnceWhenNotGranted() async {
        permissions.statuses[.accessibility] = .notDetermined
        await controller.modeDidChange(to: .automatic)
        XCTAssertEqual(permissions.requests, [.accessibility])
    }

    func testModeDidChangeToOffTouchesNothing() async {
        permissions.statuses[.accessibility] = .notDetermined
        await controller.modeDidChange(to: .off)
        XCTAssertTrue(permissions.statusCalls.isEmpty)
        XCTAssertTrue(permissions.requests.isEmpty)
    }
}
