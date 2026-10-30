import AppKit
import KeyboardShortcuts

@MainActor
enum MirrorService {
    private static var workspaceTokens: [NSObjectProtocol] = []
    private static var lockToken: NSObjectProtocol?

    static func start() {
        KeyboardShortcuts.onKeyDown(for: .toggleMirror) {
            Task { @MainActor in MirrorPanelController.shared.toggle() }
        }
        guard workspaceTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ]
        workspaceTokens = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { MirrorPanelController.shared.close() }
            }
        }
        lockToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { MirrorPanelController.shared.close() }
        }
    }

    static func stop() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach { center.removeObserver($0) }
        workspaceTokens.removeAll()
        if let lockToken {
            DistributedNotificationCenter.default().removeObserver(lockToken)
        }
        lockToken = nil
        MirrorPanelController.shared.close()
    }
}
