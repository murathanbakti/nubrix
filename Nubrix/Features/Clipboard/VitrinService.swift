import AppKit
import Combine
import Defaults
import KeyboardShortcuts

@MainActor
enum VitrinService {
    private static var observers = Set<AnyCancellable>()

    static func start() {
        observers.removeAll()
        syncMonitor()
        ScreenshotWatcher.shared.refresh()
        Publishers.MergeMany([
            Defaults.publisher(.vitrinEnabled, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.vitrinCaptureImages, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.vitrinCaptureScreenshots, options: []).map { _ in () }.eraseToAnyPublisher(),
            ScreenshotAccess.shared.$folder.dropFirst().map { _ in () }.eraseToAnyPublisher()
        ])
        .receive(on: RunLoop.main)
        .sink { _ in
            MainActor.assumeIsolated {
                syncMonitor()
                ScreenshotWatcher.shared.refresh()
            }
        }
        .store(in: &observers)
        ClipStore.shared.$vaultState
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { _ in
                MainActor.assumeIsolated { ScreenshotWatcher.shared.refresh() }
            }
            .store(in: &observers)
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)
                .map { _ in () },
            DistributedNotificationCenter.default()
                .publisher(for: Notification.Name("com.apple.screenIsUnlocked"))
                .map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { _ in
            MainActor.assumeIsolated { ClipStore.shared.retryIfKeychainLocked() }
        }
        .store(in: &observers)
        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screenIsLocked"))
            .receive(on: RunLoop.main)
            .sink { _ in
                MainActor.assumeIsolated { ClipStore.shared.dropSearchIndex() }
            }
            .store(in: &observers)
        Defaults.publisher(.vitrinRetentionDays, options: [])
            .receive(on: RunLoop.main)
            .sink { _ in
                MainActor.assumeIsolated { ClipStore.shared.sweep() }
            }
            .store(in: &observers)
        KeyboardShortcuts.onKeyDown(for: .toggleVitrin) {
            Task { @MainActor in VitrinPanelController.shared.toggle() }
        }
    }

    private static func syncMonitor() {
        if Defaults[.vitrinEnabled] {
            ClipStore.shared.start()
            if !ScreenshotAccess.shared.hasAccess { ScreenshotAccess.shared.restore() }
            ClipboardMonitor.shared.start()
        } else {
            ClipboardMonitor.shared.stop()
            ScreenshotWatcher.shared.stop()
            ScreenshotBannerStore.shared.dismissBanner()
            VitrinPanelController.shared.close()
            ScreenshotAccess.shared.release()
            ClipStore.shared.shutdown()
        }
    }

    static func stop() {
        observers.removeAll()
        ScreenshotWatcher.shared.stop()
        ScreenshotBannerStore.shared.dismissBanner()
        ClipboardMonitor.shared.stop()
        ClipStore.shared.shutdown()
        VitrinPanelController.shared.close()
    }
}
