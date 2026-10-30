import AppKit
import Defaults
import SwiftUI

@MainActor
final class NotchExtensionHost: ObservableObject {
    static let shared = NotchExtensionHost()

    enum Phase {
        case idle
        case opening
        case open
        case closing
    }

    private struct Request {
        let id: String
        var mode: NotchExtensionMode
        let screenUUID: String?
        let activatesOnPresent: Bool
        let handlesEscape: Bool
        let content: AnyView
        let onPresented: (() -> Void)?
        let onWillDismiss: (() -> Void)?
        let onDismissed: (() -> Void)?
    }

    private struct Session {
        var request: Request
        let screen: NSScreen
        var geometry: NotchExtensionGeometry
        var notchHeight: CGFloat
        var willDismissCalled = false
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var currentID: String?
    private var session: Session?
    private var pending: Request?
    private var overlay: NotchTransitionWindow?
    private var overlayHost: NSHostingView<AnyView>?
    private var panel: NotchExtensionPanel?
    private var panelModel: NotchExtensionPanelModel?
    private var transition: NotchExtensionTransition?
    private var generation = 0
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var activatedFrom: NSRunningApplication?
    private var didActivateApp = false

    private init() {
        installSystemObservers()
    }

    func isPresenting(_ id: String) -> Bool {
        session?.request.id == id && phase != .closing
    }

    func present<Content: View>(
        id: String,
        mode: NotchExtensionMode,
        screenUUID: String? = nil,
        activatesOnPresent: Bool = false,
        handlesEscape: Bool = true,
        onPresented: (() -> Void)? = nil,
        onWillDismiss: (() -> Void)? = nil,
        onDismissed: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        let request = Request(
            id: id,
            mode: mode,
            screenUUID: screenUUID,
            activatesOnPresent: activatesOnPresent,
            handlesEscape: handlesEscape,
            content: AnyView(content()),
            onPresented: onPresented,
            onWillDismiss: onWillDismiss,
            onDismissed: onDismissed
        )
        if session != nil {
            if session?.request.id == request.id, phase != .closing { return }
            pending = request
            if phase != .closing { beginClosing(animated: true) }
            return
        }
        begin(request)
    }

    func toggle<Content: View>(
        id: String,
        mode: NotchExtensionMode,
        screenUUID: String? = nil,
        activatesOnPresent: Bool = false,
        handlesEscape: Bool = true,
        onPresented: (() -> Void)? = nil,
        onWillDismiss: (() -> Void)? = nil,
        onDismissed: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        if isPresenting(id) {
            dismiss(id: id)
        } else {
            present(
                id: id,
                mode: mode,
                screenUUID: screenUUID,
                activatesOnPresent: activatesOnPresent,
                handlesEscape: handlesEscape,
                onPresented: onPresented,
                onWillDismiss: onWillDismiss,
                onDismissed: onDismissed,
                content: content
            )
        }
    }

    func dismiss(id: String? = nil, animated: Bool = true) {
        pending = nil
        guard let session else { return }
        if let id, session.request.id != id { return }
        if phase == .closing {
            if !animated { finishClose() }
            return
        }
        beginClosing(animated: animated)
    }

    func resize(to size: CGSize, animated: Bool = true) {
        guard var current = session, current.request.mode.isDetached, let panel else { return }
        current.request.mode = current.request.mode.resized(to: size)
        let screenFrame = current.screen.frame
        let old = panel.frame
        var frame = NSRect(x: old.midX - size.width / 2, y: old.midY - size.height / 2, width: size.width, height: size.height)
        let visible = current.screen.visibleFrame
        frame.origin.x = min(max(frame.origin.x, screenFrame.minX + 8), screenFrame.maxX - size.width - 8)
        frame.origin.y = min(max(frame.origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        current.geometry = makeGeometry(screen: current.screen, mode: current.request.mode)
        session = current
        panel.setFrame(frame, display: true, animate: animated)
        panel.invalidateShadow()
    }

    private func begin(_ request: Request) {
        guard let screen = resolveScreen(request.screenUUID) else { return }
        let uuid = screen.displayUUID
        let notchSize = getClosedNotchSize(screenUUID: uuid)
        let geometry = makeGeometry(screen: screen, mode: request.mode, notchSize: notchSize)
        session = Session(request: request, screen: screen, geometry: geometry, notchHeight: notchSize.height)
        currentID = request.id
        phase = .opening
        generation += 1
        let current = generation
        let closeRequest = NotchCloseRequest()
        NotificationCenter.default.post(name: .notchExtensionRequestNotchClose, object: closeRequest)
        let delay: Duration = closeRequest.didClose ? .milliseconds(300) : .zero
        Task { @MainActor [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard let self, self.generation == current, self.phase == .opening else { return }
            self.startOpening()
        }
    }

    private func startOpening() {
        guard let session else { return }
        installMonitors()
        let detached = session.request.mode.isDetached
        let transition = NotchExtensionTransition.opening(detached: detached)
        self.transition = transition
        showOverlay(geometry: session.geometry, screen: session.screen, transition: transition)
        let current = generation
        schedule(after: transition.duration, generation: current) { [weak self] in
            self?.handOver()
        }
    }

    private func handOver() {
        guard let session, phase == .opening else { return }
        let detached = session.request.mode.isDetached
        let screen = session.screen
        let frame = appKitFrame(session.geometry.target, screen: screen)

        overlayHost?.rootView = AnyView(NotchGooCanvas(geometry: session.geometry, progress: 1))

        let model = NotchExtensionPanelModel(detached: detached, notchHeight: session.notchHeight)
        let panel = NotchExtensionPanel(frame: frame)
        panel.draggable = detached
        panel.hasShadow = detached
        let view = NotchExtensionPanelView(
            model: model,
            content: session.request.content,
            dismiss: { [weak self] in self?.dismiss() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        panel.contentView = hosting
        panel.alphaValue = detached ? 0 : 1
        panel.orderFrontRegardless()
        overlay?.orderFrontRegardless()
        self.panel = panel
        self.panelModel = model
        phase = .open
        transition = nil

        if detached {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
        panel.invalidateShadow()
        let current = generation
        schedule(after: 0.16, generation: current) { [weak self] in
            self?.removeOverlay()
            self?.panelModel?.contentVisible = true
            self?.panel?.invalidateShadow()
        }
        if session.request.activatesOnPresent {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                activatedFrom = front
                didActivateApp = true
            }
            NSApp.activate()
            panel.makeKey()
        }
        session.request.onPresented?()
    }

    private func beginClosing(animated: Bool) {
        guard var current = session, phase != .closing else { return }
        if !current.willDismissCalled {
            current.willDismissCalled = true
            session = current
            current.request.onWillDismiss?()
        }
        restorePreviousApp()
        let hadOverlayOrPanel = overlay != nil || panel != nil
        guard animated, hadOverlayOrPanel else {
            finishClose()
            return
        }
        let detached = current.request.mode.isDetached
        if detached, let panel {
            let frame = panel.frame
            let rect = CGRect(
                x: frame.minX - current.screen.frame.minX,
                y: current.screen.frame.maxY - frame.maxY,
                width: frame.width,
                height: frame.height
            )
            current.geometry = makeGeometry(screen: current.screen, mode: current.request.mode, targetOverride: rect)
            session = current
        }
        let from: CGFloat
        if phase == .open {
            from = 1
        } else if let transition {
            from = min(1, transition.progress(at: Date()))
        } else {
            from = 0
        }
        phase = .closing
        generation += 1
        let next = NotchExtensionTransition.closing(detached: detached, from: from)
        transition = next
        panelModel?.contentVisible = false
        showOverlay(geometry: current.geometry, screen: current.screen, transition: next)
        if let panel {
            panel.orderOut(nil)
            panel.contentView = nil
            self.panel = nil
            panelModel = nil
        }
        schedule(after: next.duration, generation: generation) { [weak self] in
            self?.finishClose()
        }
    }

    private func finishClose() {
        generation += 1
        removeOverlay()
        if let panel {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panel = nil
        panelModel = nil
        transition = nil
        removeMonitors()
        restorePreviousApp()
        let finished = session
        session = nil
        currentID = nil
        phase = .idle
        if let finished, !finished.willDismissCalled {
            finished.request.onWillDismiss?()
        }
        finished?.request.onDismissed?()
        if let next = pending {
            pending = nil
            begin(next)
        }
    }

    private func restorePreviousApp() {
        guard didActivateApp else { return }
        didActivateApp = false
        let previous = activatedFrom
        activatedFrom = nil
        guard NSApp.isActive,
            let previous,
            !previous.isTerminated,
            NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        else { return }
        previous.activate()
    }

    private func showOverlay(geometry: NotchExtensionGeometry, screen: NSScreen, transition: NotchExtensionTransition) {
        let root = AnyView(NotchTransitionView(geometry: geometry, transition: transition))
        if let overlayHost, let overlay {
            overlay.setFrame(appKitFrame(geometry.canvas, screen: screen), display: false)
            overlayHost.rootView = root
            overlay.orderFrontRegardless()
            return
        }
        let frame = appKitFrame(geometry.canvas, screen: screen)
        let window = NotchTransitionWindow(frame: frame)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        window.contentView = hosting
        window.orderFrontRegardless()
        overlay = window
        overlayHost = hosting
    }

    private func removeOverlay() {
        overlay?.orderOut(nil)
        overlay?.contentView = nil
        overlay = nil
        overlayHost = nil
    }

    private func schedule(after seconds: TimeInterval, generation expected: Int, _ action: @escaping @MainActor () -> Void) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.generation == expected else { return }
            action()
        }
    }

    private func resolveScreen(_ uuid: String?) -> NSScreen? {
        if let uuid, let screen = NSScreen.screen(withUUID: uuid) { return screen }
        return NSScreen.screen(withUUID: BoringViewCoordinator.shared.selectedScreenUUID) ?? NSScreen.main
    }

    private func makeGeometry(screen: NSScreen, mode: NotchExtensionMode, notchSize: CGSize? = nil, targetOverride: CGRect? = nil) -> NotchExtensionGeometry {
        let size = notchSize ?? getClosedNotchSize(screenUUID: screen.displayUUID)
        return NotchExtensionGeometry.make(
            screenSize: screen.frame.size,
            visibleTopInset: screen.frame.maxY - screen.visibleFrame.maxY,
            visibleHeight: screen.visibleFrame.height,
            notchSize: size,
            mode: mode,
            targetOverride: targetOverride
        )
    }

    private func appKitFrame(_ rect: CGRect, screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.frame.minX + rect.minX,
            y: screen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func installMonitors() {
        removeMonitors()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] event in
            guard let self else { return event }
            if let window = event.window, window !== self.panel, !(window is BoringNotchSkyLightWindow) {
                Task { @MainActor in self.dismiss() }
            }
            return event
        }) {
            monitors.append(local)
        }
        if let key = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, event.keyCode == 53, self.session?.request.handlesEscape ?? true, let panel = self.panel, panel.isKeyWindow else { return event }
            Task { @MainActor in self.dismiss() }
            return nil
        }) {
            monitors.append(key)
        }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    private func installSystemObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { NotchExtensionHost.shared.dismiss(animated: false) }
            })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { NotchExtensionHost.shared.dismiss(animated: false) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { NotchExtensionHost.shared.dismiss(animated: false) }
        })
    }
}
