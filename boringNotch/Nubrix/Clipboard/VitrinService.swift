import AppKit
import Combine
import Defaults
import KeyboardShortcuts

@MainActor
enum VitrinService {
    private static var observers = Set<AnyCancellable>()

    static func start() {
        ClipStore.shared.start()
        ClipboardMonitor.shared.start()
        ScreenshotAccess.shared.restore()
        ScreenshotWatcher.shared.refresh()
        observers.removeAll()
        Publishers.MergeMany([
            Defaults.publisher(.vitrinEnabled, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.vitrinCaptureImages, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.vitrinCaptureScreenshots, options: []).map { _ in () }.eraseToAnyPublisher(),
            ScreenshotAccess.shared.$folder.dropFirst().map { _ in () }.eraseToAnyPublisher()
        ])
        .receive(on: RunLoop.main)
        .sink { _ in
            MainActor.assumeIsolated { ScreenshotWatcher.shared.refresh() }
        }
        .store(in: &observers)
        KeyboardShortcuts.onKeyDown(for: .toggleVitrin) {
            Task { @MainActor in VitrinPanelController.shared.toggle() }
        }
    }

    static func stop() {
        observers.removeAll()
        ScreenshotWatcher.shared.stop()
        ScreenshotBannerStore.shared.dismissBanner()
        ClipboardMonitor.shared.stop()
        ClipStore.shared.stop()
        VitrinPanelController.shared.close()
    }
}
