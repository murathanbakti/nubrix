//
//  NubrixApp.swift
//  NubrixApp
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI

let isRunningUnderXCTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    || NSClassFromString("XCTestCase") != nil

@main
struct NubrixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Environment(\.openWindow) var openWindow

    init() {
        guard !isRunningUnderXCTest else { return }
        NubrixMigration.run()
        DefaultsMigration.run()
    }

    var body: some Scene {
        MenuBarExtra("Nubrix", systemImage: "sparkle", isInserted: $showMenuBarIcon) {
            UpdateMenuItems()
            Button("Settings") {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            }
            .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
            Divider()
            Button("Restart Nubrix") {
                ApplicationRelauncher.restart()
            }
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(self)
            }
            .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var windows: [String: NSWindow] = [:] // UUID -> NSWindow
    var viewModels: [String: NubrixViewModel] = [:] // UUID -> NubrixViewModel
    var window: NSWindow?
    let vm: NubrixViewModel = .init()
    @ObservedObject var coordinator = NubrixCoordinator.shared
    var quickShareService = QuickShareService.shared
    var whatsNewWindow: NSWindow?
    var timer: Timer?
    var closeNotchTask: Task<Void, Never>?
    private var previousScreens: [NSScreen]?
    private var onboardingWindowController: NSWindowController?
    private var onboardingCloseObserver: NSObjectProtocol?
    private var screenLockedObserver: Any?
    private var screenUnlockedObserver: Any?
    private var isScreenLocked: Bool = false
    private var windowScreenDidChangeObserver: Any?
    private var dragDetectors: [String: DragDetector] = [:] // UUID -> DragDetector
    private var terminationSignalSource: DispatchSourceSignal?
    private var terminationRequested = false
    private var screenRefreshTask: Task<Void, Never>?
    private var pendingChangeAlpha = false
    private var pendingAdjust = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if onboardingWindowController != nil { LaunchFlow().onboardingDidAppear() }
        AgentEventServer.shared.stop()
        VitrinService.stop()
        MirrorService.stop()
        NubrixCalendarService.stop()
        UpdateStore.shared.stop()
        NotificationCenter.default.removeObserver(self)
        if let observer = screenLockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenLockedObserver = nil
        }
        if let observer = screenUnlockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenUnlockedObserver = nil
        }
        MusicManager.shared.destroy()
        DisplayReconfigurationWatcher.shared.stop()
        screenRefreshTask?.cancel()
        ScreenShareMonitor.shared.stop()
        cleanupDragDetectors()
        cleanupWindows()
        XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
    }

    @MainActor
    func onScreenLocked(_ notification: Notification) {
        isScreenLocked = true
        if !Defaults[.showOnLockScreen] {
            cleanupWindows()
        } else {
            enableSkyLightOnAllWindows()
        }
    }

    @MainActor
    func onScreenUnlocked(_ notification: Notification) {
        isScreenLocked = false
        if !Defaults[.showOnLockScreen] {
            adjustWindowPosition(changeAlpha: true)
        } else {
            disableSkyLightOnAllWindows()
        }
    }
    
    @MainActor
    private func enableSkyLightOnAllWindows() {
        if Defaults[.showOnAllDisplays] {
            windows.values.forEach { window in
                if let skyWindow = window as? NubrixSkyLightPanel {
                    skyWindow.enableSkyLight()
                }
            }
        } else {
            if let skyWindow = window as? NubrixSkyLightPanel {
                skyWindow.enableSkyLight()
            }
        }
    }
    
    @MainActor
    private func disableSkyLightOnAllWindows() {
        // Delay disabling SkyLight to avoid flicker during unlock transition
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                if Defaults[.showOnAllDisplays] {
                    self.windows.values.forEach { window in
                        if let skyWindow = window as? NubrixSkyLightPanel {
                            skyWindow.disableSkyLight()
                        }
                    }
                } else {
                    if let skyWindow = self.window as? NubrixSkyLightPanel {
                        skyWindow.disableSkyLight()
                    }
                }
            }
        }
    }

    private func cleanupWindows(shouldInvert: Bool = false) {
        let shouldCleanupMulti = shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays]
        
        if shouldCleanupMulti {
            windows.values.forEach { window in
                window.close()
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window = window {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            if let obs = windowScreenDidChangeObserver {
                NotificationCenter.default.removeObserver(obs)
                windowScreenDidChangeObserver = nil
            }
            self.window = nil
        }
    }

    private func cleanupDragDetectors() {
        dragDetectors.values.forEach { detector in
            detector.stopMonitoring()
        }
        dragDetectors.removeAll()
    }

    private func setupDragDetectors() {
        cleanupDragDetectors()

        guard Defaults[.expandedDragDetection], Defaults[.nubrixShelf] else { return }

        if Defaults[.showOnAllDisplays] {
            for screen in NSScreen.screens {
                setupDragDetectorForScreen(screen)
            }
        } else {
            let preferredScreen: NSScreen? = window?.screen
                ?? NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
                ?? NSScreen.main

            if let screen = preferredScreen {
                setupDragDetectorForScreen(screen)
            }
        }
    }

    private func setupDragDetectorForScreen(_ screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        let screenFrame = screen.frame
        let notchHeight = openNotchSize.height
        let notchWidth = openNotchSize.width
        
        // Create notch region at the top-center of the screen where an open notch would occupy
        let notchRegion = CGRect(
            x: screenFrame.midX - notchWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )
        
        let detector = DragDetector(notchRegion: notchRegion)
        
        detector.onDragEntersNotchRegion = { [weak self] in
            Task { @MainActor in
                self?.handleDragEntersNotchRegion(onScreen: screen)
            }
        }
        
        dragDetectors[uuid] = detector
        detector.startMonitoring()
    }

    private func handleDragEntersNotchRegion(onScreen screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        if Defaults[.showOnAllDisplays], let viewModel = viewModels[uuid] {
            viewModel.open()
            coordinator.currentView = .shelf
        } else if !Defaults[.showOnAllDisplays], let windowScreen = window?.screen, screen == windowScreen {
            vm.open()
            coordinator.currentView = .shelf
        }
    }

    private func createNubrixPanel(for screen: NSScreen, with viewModel: NubrixViewModel) -> NSWindow {
        let rect = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
        
        let window = NubrixSkyLightPanel(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)
        
        // Enable SkyLight only when screen is locked
        if isScreenLocked {
            window.enableSkyLight()
        } else {
            window.disableSkyLight()
        }

        window.contentView = NSHostingView(
            rootView: ContentView()
                .environmentObject(viewModel)
        )

        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)
        followNotchHeight(of: window, viewModel: viewModel)

        // Observe when the window's screen changes so we can update drag detectors
        windowScreenDidChangeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setupDragDetectors()
                }
        }
        return window
    }

    /// The window is only as tall as the open notch needs: the normal height, and taller while the
    /// Controls tab is open. When the notch is closed or on another tab the window is exactly the size
    /// it always was, so the extra transparent area never sits over apps below. Growing happens right
    /// away (before the notch animates down), shrinking after the close animation has finished.
    ///
    /// The resize waits for the next main-queue turn: `@Published` emits before it stores the new
    /// value, and `setFrame(display: true)` makes SwiftUI redraw right then, with the old tab and
    /// size, so it never noticed the change. Clicking the Controls tab needed a second click.
    private func followNotchHeight(of window: NSWindow, viewModel: NubrixViewModel) {
        var shrinkTask: Task<Void, Never>?
        let apply: @MainActor (CGFloat) -> Void = { [weak window] height in
            guard let window, abs(window.frame.height - height) > 0.5 else { return }
            let f = window.frame
            window.setFrame(NSRect(x: f.minX, y: f.maxY - height, width: f.width, height: height), display: true)
        }
        Publishers.CombineLatest(viewModel.$notchState, viewModel.$notchSize)
            .map { state, size in
                state == .open ? notchWindowHeight(forOpenNotchHeight: size.height) : windowSize.height
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak window] target in
                shrinkTask?.cancel()
                guard let window else { return }
                if target >= window.frame.height {
                    MainActor.assumeIsolated { apply(target) }
                } else {
                    shrinkTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(700))
                        guard !Task.isCancelled else { return }
                        apply(target)
                    }
                }
            }
            .store(in: &viewModel.cancellables)
    }

    @MainActor
    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha {
            window.alphaValue = 0
        }

        let screenFrame = screen.frame
        window.setFrameOrigin(
            NSPoint(
                x: screenFrame.origin.x + (screenFrame.width / 2) - window.frame.width / 2,
                y: screenFrame.origin.y + screenFrame.height - window.frame.height
            ))
        window.alphaValue = 1
    }

    private func quitOnTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { exit(EXIT_SUCCESS) }
                if self.terminationRequested { exit(EXIT_SUCCESS) }
                self.terminationRequested = true
                NSApp.terminate(nil)
            }
        }
        source.resume()
        terminationSignalSource = source
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningUnderXCTest else { return }
        quitOnTerminationSignal()
        AgentEventServer.shared.applyPolicy()
        GitHubStore.shared.start {
            AgentSessionStore.shared.sessions.compactMap { session in
                session.remote.map { GitHubSessionRef(repo: $0, branch: session.branch) }
            }
        }
        ClaudePlanUsageStore.shared.start()
        SystemNotificationStore.shared.start()
        DockBadgeStore.shared.start()
        VitrinService.start()
        MirrorService.start()
        NubrixCalendarService.start()
        MusicManager.shared.start()
        DeviceBatteryStore.shared.start()
        EverydayAlertStore.shared.start()
        UpdateStore.shared.start()
        ScreenShareMonitor.shared.start()
        startDisplayReconfigurationWatcher()
        Task { await HookKitStore.shared.launchCheck() }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: Notification.Name.selectedScreenChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition(changeAlpha: true)
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.notchHeightChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.automaticallySwitchDisplayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self, let window = self.window else { return }
            Task { @MainActor in
                window.alphaValue = self.coordinator.selectedScreenUUID == self.coordinator.preferredScreenUUID ? 1 : 0
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.cleanupWindows(shouldInvert: true)
                self.adjustWindowPosition(changeAlpha: true)
                self.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.expandedDragDetectionChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setupDragDetectors()
            }
        }

        // Use closure-based observers for DistributedNotificationCenter and keep tokens for removal
        screenLockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenLocked(notification)
                }
        }

        screenUnlockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenUnlocked(notification)
                }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self = self, Defaults[.mediaControlEnabled] else { return }
            if Defaults[.sneakPeekStyles] == .inline {
                let newStatus = !self.coordinator.expandingView.show
                self.coordinator.toggleExpandingView(status: newStatus, type: .music)
            } else {
                self.coordinator.toggleSneakPeek(
                    status: !self.coordinator.sneakPeek.show,
                    type: .music,
                    duration: 3.0
                )
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            Task { [weak self] in
                guard let self = self else { return }

                let mouseLocation = NSEvent.mouseLocation

                var viewModel = self.vm

                if Defaults[.showOnAllDisplays] {
                    for screen in NSScreen.screens {
                        if screen.frame.contains(mouseLocation) {
                            if let uuid = screen.displayUUID, let screenViewModel = self.viewModels[uuid] {
                                viewModel = screenViewModel
                                break
                            }
                        }
                    }
                }

                self.closeNotchTask?.cancel()
                self.closeNotchTask = nil

                switch viewModel.notchState {
                case .closed:
                    await MainActor.run {
                        viewModel.open()
                    }

                    let task = Task { [weak viewModel] in
                        do {
                            try await Task.sleep(for: .seconds(3))
                            await MainActor.run {
                                viewModel?.close()
                            }
                        } catch { }
                    }
                    self.closeNotchTask = task
                case .open:
                    await MainActor.run {
                        viewModel.close()
                    }
                }
            }
        }

        if !Defaults[.showOnAllDisplays] {
            let viewModel = self.vm
            let window = createNubrixPanel(
                for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
            self.window = window
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }

        setupDragDetectors()

        let launchFlow = LaunchFlow()
        let isFirstLaunch = launchFlow.isFirstLaunch
        let launchAction = launchFlow.initialAction()
        switch launchAction {
        case .onboarding:
            // Fresh install: record the version as seen without showing What's New.
            WhatsNewWindowController.shared.presentIfNeeded(isFirstLaunch: true)
            DispatchQueue.main.async {
                self.showOnboardingWindow()
            }
        case .fdaReturn(let origin):
            Task { @MainActor in await self.handleFDAReturn(origin) }
        case .none:
            // Normal route only; shown a couple of seconds after launch.
            WhatsNewWindowController.shared.presentIfNeeded(isFirstLaunch: isFirstLaunch)
        }

        previousScreens = NSScreen.screens
    }

    private func handleFDAReturn(_ origin: FDAOrigin) async {
        let outcome = await LaunchFlow().resolveFDAReturn(origin: origin, client: Permissions.client)
        switch origin {
        case .settings:
            SettingsNavigation.shared.open(.notifications)
        case .permissions:
            SettingsNavigation.shared.open(.permissions)
        case .notch:
            coordinator.currentView = .notifications
            if Defaults[.showOnAllDisplays], let uuid = NSScreen.main?.displayUUID, let model = viewModels[uuid] {
                model.open()
            } else {
                vm.open()
            }
        }
        if case .stillOff = outcome { LaunchFlow().beginFDAGrant(origin: origin) }
        FullDiskAccessGuide.showReturn()
    }

    func deviceHasNotch() -> Bool {
        if #available(macOS 12.0, *) {
            for screen in NSScreen.screens {
                if screen.safeAreaInsets.top > 0 {
                    return true
                }
            }
        }
        return false
    }

    @objc func screenConfigurationDidChange() {
        scheduleScreenRefresh()
    }

    /// While the displays are being reconfigured (AirPlay starting, a display added or mirrored) the
    /// notch space is taken off screen and no window is touched; one refresh runs after things settle.
    private func startDisplayReconfigurationWatcher() {
        let watcher = DisplayReconfigurationWatcher.shared
        watcher.onBegin = {
            NotchSpaceManager.shared.notchSpace.hide()
        }
        watcher.onSettled = { [weak self] in
            self?.scheduleScreenRefresh()
        }
        watcher.start()
    }

    /// Coalesces screen changes into one refresh that waits for the displays to settle.
    private func scheduleScreenRefresh(changeAlpha: Bool = false, adjust: Bool = false) {
        pendingChangeAlpha = pendingChangeAlpha || changeAlpha
        pendingAdjust = pendingAdjust || adjust
        screenRefreshTask?.cancel()
        screenRefreshTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                let gate = DisplayReconfigurationWatcher.shared.gate
                try? await Task.sleep(for: .seconds(gate.delayBeforeRefresh(at: Date())))
                if Task.isCancelled { return }
                if DisplayReconfigurationWatcher.shared.isQuiet {
                    self.refreshScreens()
                    return
                }
            }
        }
    }

    private func refreshScreens() {
        NotchSpaceManager.shared.notchSpace.show()
        let changeAlpha = pendingChangeAlpha
        let adjust = pendingAdjust
        pendingChangeAlpha = false
        pendingAdjust = false
        let currentScreens = NSScreen.screens

        let screensChanged =
            currentScreens.count != previousScreens?.count
            || Set(currentScreens.compactMap { $0.displayUUID })
                != Set(previousScreens?.compactMap { $0.displayUUID } ?? [])
            || Set(currentScreens.map { $0.frame }) != Set(previousScreens?.map { $0.frame } ?? [])
            || Set(currentScreens.filter(\.hostsNotch).compactMap { $0.displayUUID })
                != Set(previousScreens?.filter(\.hostsNotch).compactMap { $0.displayUUID } ?? [])

        previousScreens = currentScreens

        if screensChanged {
            cleanupWindows()
            adjustWindowPosition(changeAlpha: changeAlpha)
            setupDragDetectors()
        } else if changeAlpha || adjust {
            adjustWindowPosition(changeAlpha: changeAlpha)
        }
    }

    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        // Never create, move or order windows while the displays are being reconfigured.
        guard DisplayReconfigurationWatcher.shared.isQuiet else {
            scheduleScreenRefresh(changeAlpha: changeAlpha, adjust: true)
            return
        }
        // A display that only mirrors another one gets no window.
        let hostScreens = NSScreen.screens.filter(\.hostsNotch)
        if Defaults[.showOnAllDisplays] {
            let currentScreenUUIDs = Set(hostScreens.compactMap { $0.displayUUID })

            // Remove windows for screens that no longer exist
            for uuid in windows.keys where !currentScreenUUIDs.contains(uuid) {
                if let window = windows[uuid] {
                    window.close()
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                    windows.removeValue(forKey: uuid)
                    viewModels.removeValue(forKey: uuid)
                }
            }

            // Create or update windows for all screens
            for screen in hostScreens {
                guard let uuid = screen.displayUUID else { continue }
                
                if windows[uuid] == nil {
                    let viewModel = NubrixViewModel(screenUUID: uuid)
                    let window = createNubrixPanel(for: screen, with: viewModel)

                    windows[uuid] = window
                    viewModels[uuid] = viewModel
                }

                if let window = windows[uuid], let viewModel = viewModels[uuid] {
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)
                    // A screen without a camera housing (HDMI, AirPlay) still gets the notch;
                    // make sure its window is on screen and sized for that screen.
                    if !window.isVisible { window.orderFrontRegardless() }

                    if viewModel.notchState == .closed {
                        viewModel.screenUUID = uuid
                        viewModel.close()
                    }
                }
            }
        } else {
            let selectedScreen: NSScreen

            if let preferredScreen = NSScreen.screen(withUUID: coordinator.preferredScreenUUID ?? ""), preferredScreen.hostsNotch {
                coordinator.selectedScreenUUID = coordinator.preferredScreenUUID ?? ""
                selectedScreen = preferredScreen
            } else if Defaults[.automaticallySwitchDisplay], let mainScreen = NSScreen.main, mainScreen.hostsNotch,
                      let mainUUID = mainScreen.displayUUID {
                coordinator.selectedScreenUUID = mainUUID
                selectedScreen = mainScreen
            } else {
                if let window = window {
                    window.alphaValue = 0
                }
                return
            }

            vm.screenUUID = selectedScreen.displayUUID
            vm.notchSize = getClosedNotchSize(screenUUID: selectedScreen.displayUUID)

            if window == nil {
                window = createNubrixPanel(for: selectedScreen, with: vm)
            }

            if let window = window {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)

                if vm.notchState == .closed {
                    vm.close()
                }
            }
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }

    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc func quitAction() {
        NSApplication.shared.terminate(self)
    }

    private func showOnboardingWindow(step: OnboardingStep = .welcome) {
        if onboardingWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Onboarding"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.contentView = NSHostingView(
                rootView: OnboardingView(
                    step: step,
                    onFinish: {
                        window.orderOut(nil)
//                        NSApp.setActivationPolicy(.accessory)
                        window.close()
                        NSApp.deactivate()
                    },
                    onOpenSettings: {
                        window.close()
                        SettingsWindowController.shared.showWindow()
                    }
                ))
            window.isRestorable = false
            window.isReleasedWhenClosed = false
            window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")

            onboardingWindowController = NSWindowController(window: window)

            onboardingCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    NubrixCoordinator.shared.firstLaunch = false
                    if let observer = self?.onboardingCloseObserver {
                        NotificationCenter.default.removeObserver(observer)
                    }
                    self?.onboardingCloseObserver = nil
                    self?.onboardingWindowController = nil
                }
            }
        }

        LaunchFlow().onboardingDidAppear()
//        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        onboardingWindowController?.window?.orderFrontRegardless()
    }
}

extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
    static let expandedDragDetectionChanged = Notification.Name("expandedDragDetectionChanged")
}

extension CGRect: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }

    public static func == (lhs: CGRect, rhs: CGRect) -> Bool {
        return lhs.origin == rhs.origin && lhs.size == rhs.size
    }
}
