import AppKit
import KeyboardShortcuts

@MainActor
enum VitrinService {
    static func start() {
        ClipStore.shared.start()
        ClipboardMonitor.shared.start()
        KeyboardShortcuts.onKeyDown(for: .toggleVitrin) {
            Task { @MainActor in VitrinPanelController.shared.toggle() }
        }
    }

    static func stop() {
        ClipboardMonitor.shared.stop()
        ClipStore.shared.stop()
        VitrinPanelController.shared.close()
    }
}
