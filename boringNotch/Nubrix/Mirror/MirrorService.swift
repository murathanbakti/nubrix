import AppKit
import KeyboardShortcuts

@MainActor
enum MirrorService {
    static func start() {
        KeyboardShortcuts.onKeyDown(for: .toggleMirror) {
            Task { @MainActor in MirrorMode.shared.toggleUnderMouse() }
        }
    }

    static func stop() {
        MirrorMode.shared.exit(animated: false)
    }
}
