import AVFoundation
import AppKit
import Defaults
import SwiftUI

final class MirrorPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            onEscape?()
            return
        }
        super.sendEvent(event)
    }
}

final class MirrorPreviewNSView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        previewLayer.videoGravity = .resizeAspectFill
        layer = previewLayer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setMirrored(_ mirrored: Bool) {
        guard let connection = previewLayer.connection else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = mirrored
        }
    }
}

struct MirrorPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeNSView(context: Context) -> MirrorPreviewNSView {
        let view = MirrorPreviewNSView(session: session)
        view.setMirrored(mirrored)
        return view
    }

    func updateNSView(_ view: MirrorPreviewNSView, context: Context) {
        view.setMirrored(mirrored)
    }
}

struct MirrorPanelRoot: View {
    @ObservedObject var camera: MirrorCamera
    @Default(.mirrorSizeIndex) private var sizeIndex
    @Default(.mirrorFlipped) private var flipped
    let onSize: (Int) -> Void
    let onClose: () -> Void

    var body: some View {
        MirrorChromeView(
            state: camera.state,
            sizeIndex: MirrorMetrics.clamp(sizeIndex),
            preview: MirrorPreviewView(session: camera.session, mirrored: flipped),
            onFlip: { flipped.toggle() },
            onSize: onSize,
            onClose: onClose,
            onOpenSettings: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
        )
    }
}

@MainActor
final class MirrorPanelController: ObservableObject {
    static let shared = MirrorPanelController()

    @Published private(set) var isVisible = false

    private var panel: MirrorPanel?
    private let camera = MirrorCamera()
    private var outsideClickMonitor: Any?
    private var closeToken = 0

    func toggle() {
        isVisible ? close() : show()
    }

    func show() {
        guard !isVisible else { return }
        closeToken += 1
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let target = targetFrame(sizeIndex: MirrorMetrics.clamp(Defaults[.mirrorSizeIndex]), anchoredTo: nil)
        panel.setFrame(scaled(target, by: 0.92), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        isVisible = true
        camera.start()
        installOutsideClickMonitor()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        guard isVisible, let panel else { return }
        isVisible = false
        camera.stop()
        removeOutsideClickMonitor()
        closeToken += 1
        let token = closeToken
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.closeToken == token else { return }
                panel.orderOut(nil)
            }
        })
    }

    func setSize(_ index: Int) {
        let clamped = MirrorMetrics.clamp(index)
        Defaults[.mirrorSizeIndex] = clamped
        guard let panel, isVisible else { return }
        let frame = targetFrame(sizeIndex: clamped, anchoredTo: panel.frame)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func targetFrame(sizeIndex: Int, anchoredTo current: NSRect?) -> NSRect {
        let size = MirrorMetrics.sizes[sizeIndex]
        if let current {
            return NSRect(x: current.midX - size.width / 2, y: current.maxY - size.height, width: size.width, height: size.height)
        }
        let screen = NSScreen.screen(withUUID: BoringViewCoordinator.shared.selectedScreenUUID) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return NSRect(origin: .zero, size: size) }
        let top = screen.visibleFrame.maxY - 6
        return NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
    }

    private func scaled(_ rect: NSRect, by factor: CGFloat) -> NSRect {
        let width = rect.width * factor
        let height = rect.height * factor
        return NSRect(x: rect.midX - width / 2, y: rect.maxY - height + 6, width: width, height: height)
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    private func makePanel() -> MirrorPanel {
        let size = MirrorMetrics.sizes[MirrorMetrics.clamp(Defaults[.mirrorSizeIndex])]
        let panel = MirrorPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onEscape = { [weak self] in self?.close() }
        let root = MirrorPanelRoot(
            camera: camera,
            onSize: { [weak self] in self?.setSize($0) },
            onClose: { [weak self] in self?.close() }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
        return panel
    }
}
