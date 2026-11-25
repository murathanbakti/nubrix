import AppKit
import Combine
import Defaults
import Foundation
import os

@MainActor
final class MouseScrollController: ObservableObject {
    static let shared = MouseScrollController()

    @Published private(set) var mice: [MouseDevice] = []
    @Published private(set) var naturalScrolling = true
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var status: MouseScrollStatus = .off
    @Published private(set) var ignoredDevices: Set<String> = []

    private let monitor: MouseDeviceMonitoring
    private let tap: ScrollTapping
    private let permissionClient: (any PermissionClient)?
    private let settings: () -> MouseScrollSettings
    private let readNaturalScrolling: () -> Bool
    private let writeIgnoredDevices: (Set<String>) -> Void
    private let log = Logger(subsystem: "dev.nubrix.app", category: "MouseScroll")
    private var cancellables = Set<AnyCancellable>()
    private var distributedObserver: NSObjectProtocol?
    private var generation = 0
    private var started = false

    private var permissions: any PermissionClient { permissionClient ?? Permissions.client }

    init(
        monitor: MouseDeviceMonitoring = HIDMouseMonitor(),
        tap: ScrollTapping = ScrollWheelTap(),
        permissions: (any PermissionClient)? = nil,
        settings: @escaping () -> MouseScrollSettings = MouseScrollSettings.current,
        naturalScrolling: @escaping () -> Bool = NaturalScrolling.current,
        writeIgnoredDevices: @escaping (Set<String>) -> Void = { Defaults[.mouseScrollIgnoredDevices] = $0.sorted() }
    ) {
        self.monitor = monitor
        self.tap = tap
        self.permissionClient = permissions
        self.settings = settings
        self.readNaturalScrolling = naturalScrolling
        self.writeIgnoredDevices = writeIgnoredDevices
        self.monitor.onChange = { [weak self] mice in
            Task { @MainActor in await self?.handleMiceChange(mice) }
        }
    }

    /// Detected mice that count as a mouse for the automatic mode.
    var countedMice: [MouseDevice] { MouseDeviceClassifier.counted(mice, ignoring: ignoredDevices) }

    var mouseWheelDirection: String {
        MouseScrollDirection.name(natural: naturalScrolling, reversed: status == .reversing)
    }

    var trackpadDirection: String { naturalScrolling ? "Natural" : "Standard" }

    func start() {
        guard !started else { return }
        started = true

        Defaults.publisher(.mouseScrollMode, options: [])
            .sink { [weak self] _ in Task { @MainActor in await self?.evaluate() } }
            .store(in: &cancellables)
        Defaults.publisher(.mouseScrollReverseHorizontal, options: [])
            .sink { [weak self] _ in Task { @MainActor in await self?.evaluate() } }
            .store(in: &cancellables)
        Defaults.publisher(.mouseScrollIgnoredDevices, options: [])
            .sink { [weak self] _ in Task { @MainActor in await self?.evaluate() } }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)
            .sink { [weak self] _ in Task { @MainActor in await self?.evaluate() } }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if self.monitor.isRunning { self.mice = self.monitor.scan() }
                    await self.evaluate()
                }
            }
            .store(in: &cancellables)
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NaturalScrolling.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.evaluate() }
        }

        Task { await evaluate() }
    }

    func evaluate() async {
        generation += 1
        let current = generation
        let settings = settings()
        naturalScrolling = readNaturalScrolling()
        ignoredDevices = settings.ignoredDevices

        if settings.mode == .off {
            if monitor.isRunning {
                monitor.stop()
                log.info("Mouse detection stopped")
            }
            stopTap()
            accessibilityGranted = false
            status = .off
            return
        }

        if !monitor.isRunning {
            mice = monitor.scan()
            monitor.start()
            log.info("Mouse detection started: \(self.mice.map(\.name).joined(separator: ", "), privacy: .public)")
        }

        let granted = await permissions.status(.accessibility) == .granted
        guard current == generation else { return }
        accessibilityGranted = granted

        let want = granted && MouseScrollPolicy.shouldReverse(mode: settings.mode, mouseConnected: !countedMice.isEmpty)
        if want {
            if tap.isRunning {
                tap.update(reverseHorizontal: settings.reverseHorizontal)
            } else if tap.start(reverseHorizontal: settings.reverseHorizontal) {
                log.info("Scroll tap started")
            } else {
                log.error("Scroll tap failed to start")
            }
        } else {
            stopTap()
        }
        status = MouseScrollPolicy.status(
            mode: settings.mode,
            mouseConnected: !countedMice.isEmpty,
            accessibilityGranted: granted,
            tapRunning: tap.isRunning
        )
    }

    func handleMiceChange(_ mice: [MouseDevice]) async {
        guard self.mice != mice else { return }
        self.mice = mice
        log.info("Mice: \(mice.map(\.name).joined(separator: ", "), privacy: .public)")
        await evaluate()
    }

    func refreshDevices() {
        mice = monitor.scan()
        naturalScrolling = readNaturalScrolling()
    }

    func setCounted(_ device: MouseDevice, _ counted: Bool) {
        var ignored = ignoredDevices
        if counted { ignored.remove(device.key) } else { ignored.insert(device.key) }
        ignoredDevices = ignored
        writeIgnoredDevices(ignored)
    }

    /// Asks for Accessibility only when a mode other than Off is picked and access is missing.
    func modeDidChange(to mode: MouseScrollMode) async {
        guard mode != .off, await permissions.status(.accessibility) != .granted else { return }
        await requestAccessibility()
    }

    func requestAccessibility() async {
        _ = await permissions.request(.accessibility)
        await evaluate()
    }

    private func stopTap() {
        guard tap.isRunning else { return }
        tap.stop()
        log.info("Scroll tap stopped")
    }
}
