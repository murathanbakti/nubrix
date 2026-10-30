import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class MirrorMode: ObservableObject {
    static let shared = MirrorMode()

    private struct Host {
        weak var vm: BoringViewModel?
    }

    @Published private(set) var isActive = false

    let camera = MirrorCamera()

    private let coordinator = BoringViewCoordinator.shared
    private var hosts: [Host] = []
    private weak var activeHost: BoringViewModel?
    private var monitors: [Any] = []
    private var viewCancellable: AnyCancellable?

    private init() {
        viewCancellable = coordinator.$currentView
            .removeDuplicates()
            .sink { [weak self] view in
                MainActor.assumeIsolated { self?.setActive(view == .mirror) }
            }
    }

    func register(_ vm: BoringViewModel) {
        hosts.removeAll { $0.vm == nil }
        guard !hosts.contains(where: { $0.vm === vm }) else { return }
        hosts.append(Host(vm: vm))
    }

    func toggle() {
        if isActive {
            exit(closeNotch: true)
        } else if let vm = hostUnderMouse() {
            enter(on: vm)
        }
    }

    func toggle(on vm: BoringViewModel) {
        if isActive {
            exit(closeNotch: false)
        } else {
            enter(on: vm)
        }
    }

    func enter(on vm: BoringViewModel) {
        activeHost = vm
        if vm.notchState == .closed {
            coordinator.showOverlay(.mirror)
            withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)) {
                vm.open()
            }
        } else {
            withAnimation(.smooth) { coordinator.showOverlay(.mirror) }
        }
    }

    func exit(closeNotch: Bool) {
        guard isActive else { return }
        let host = activeHost
        if closeNotch {
            coordinator.dismissOverlay()
            host?.close()
        } else {
            withAnimation(.smooth) { coordinator.dismissOverlay() }
        }
    }

    private func hostUnderMouse() -> BoringViewModel? {
        hosts.removeAll { $0.vm == nil }
        let live = hosts.compactMap(\.vm)
        let mouse = NSEvent.mouseLocation
        let underMouse = live.first { vm in
            NSScreen.screen(withUUID: vm.screenUUID ?? coordinator.selectedScreenUUID)?.frame.contains(mouse) == true
        }
        return underMouse ?? live.first
    }

    private func setActive(_ on: Bool) {
        guard on != isActive else { return }
        isActive = on
        if on {
            SharingStateManager.shared.beginInteraction()
            camera.start()
            installMonitors()
        } else {
            camera.stop()
            removeMonitors()
            SharingStateManager.shared.endInteraction()
        }
    }

    private func installMonitors() {
        removeMonitors()
        if let click = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            Task { @MainActor in self?.exit(closeNotch: true) }
        }) {
            monitors.append(click)
        }
        if let key = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            Task { @MainActor in self?.exit(closeNotch: true) }
            return nil
        }) {
            monitors.append(key)
        }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}

struct MirrorNotchView: View {
    @ObservedObject private var mode = MirrorMode.shared
    @ObservedObject private var camera = MirrorMode.shared.camera
    @Default(.mirrorFlipped) private var flipped

    var body: some View {
        MirrorChromeView(
            state: camera.state,
            preview: MirrorPreviewView(session: camera.session, mirrored: flipped),
            onFlip: { flipped.toggle() },
            onClose: { mode.exit(closeNotch: false) },
            onOpenSettings: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
        )
    }
}
