import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class MirrorMode {
    static let shared = MirrorMode()
    static let extensionID = "dev.nubrix.mirror"

    let camera = MirrorCamera()

    private let host = NotchExtensionHost.shared

    private init() {}

    var isActive: Bool { host.isPresenting(Self.extensionID) }

    func toggle(screenUUID: String? = nil) {
        if isActive {
            exit()
        } else {
            present(screenUUID: screenUUID)
        }
    }

    func toggleUnderMouse() {
        guard Defaults[.showMirror] else { return }
        if isActive {
            exit()
            return
        }
        var uuid: String?
        if Defaults[.showOnAllDisplays] {
            let mouse = NSEvent.mouseLocation
            uuid = NSScreen.screens.first { $0.frame.contains(mouse) }?.displayUUID
        }
        present(screenUUID: uuid)
    }

    func present(screenUUID: String? = nil) {
        guard Defaults[.showMirror] else { return }
        let camera = camera
        host.present(
            id: Self.extensionID,
            mode: .detached(size: MirrorMetrics.size(large: Defaults[.mirrorLarge])),
            screenUUID: screenUUID,
            onPresented: { camera.start() },
            onWillDismiss: { camera.stop() },
            content: { MirrorPanelView(camera: camera) }
        )
    }

    func requestCameraAccess() {
        guard Defaults[.showMirror], isActive else { return }
        let host = host
        host.keepsOpenOnOutsideClick = true
        camera.requestAccess { host.keepsOpenOnOutsideClick = false }
    }

    func exit(animated: Bool = true) {
        host.dismiss(id: Self.extensionID, animated: animated)
    }
}

struct MirrorPanelView: View {
    @ObservedObject var camera: MirrorCamera
    @Default(.mirrorFlipped) private var flipped
    @Default(.mirrorLarge) private var large
    @Environment(\.notchExtensionDismiss) private var dismiss
    @State private var hovering = false

    var body: some View {
        MirrorChromeView(
            state: camera.state,
            preview: MirrorPreviewView(session: camera.session, mirrored: flipped),
            large: large,
            controlsVisible: hovering,
            onFlip: { flipped.toggle() },
            onToggleSize: {
                large.toggle()
                NotchExtensionHost.shared.resize(to: MirrorMetrics.size(large: large))
            },
            onClose: { dismiss() },
            onRequestAccess: { MirrorMode.shared.requestCameraAccess() },
            onOpenSettings: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
        )
        .notchHover { hovering = $0 }
    }
}
