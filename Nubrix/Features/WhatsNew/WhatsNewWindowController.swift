import AppKit
import Defaults
import SwiftUI

@MainActor
final class WhatsNewWindowController {
    static let shared = WhatsNewWindowController()

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    /// Called once per launch for existing users on the normal route.
    /// Records the current version as seen whether or not the window is shown.
    func presentIfNeeded(isFirstLaunch: Bool, delay: Duration = .seconds(2)) {
        guard let version = Bundle.main.releaseVersionNumber else { return }
        let notes = WhatsNewCatalog.notes(for: version)
        let show = WhatsNewPolicy.shouldShow(
            currentVersion: version,
            lastSeenVersion: Defaults[.lastSeenWhatsNewVersion],
            isFirstLaunch: isFirstLaunch,
            hasNotes: notes != nil)
        Defaults[.lastSeenWhatsNewVersion] = version
        guard show, let notes else { return }
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            self.show(notes)
        }
    }

    /// Opens the window for the running version (no-op when it has no notes).
    func showCurrentVersion() {
        guard let version = Bundle.main.releaseVersionNumber,
              let notes = WhatsNewCatalog.notes(for: version) else { return }
        show(notes)
    }

    private func show(_ notes: WhatsNewNotes) {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "What's New"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier("WhatsNewWindow")
        window.contentView = NSHostingView(rootView: WhatsNewView(
            notes: notes,
            onAction: { [weak window] in
                window?.close()
                if let tab = notes.actionTab { SettingsNavigation.shared.open(tab) }
            },
            onClose: { [weak window] in window?.close() }))
        window.setContentSize(window.contentView?.fittingSize ?? NSSize(width: 440, height: 400))
        window.center()
        self.window = window

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if let o = self?.closeObserver { NotificationCenter.default.removeObserver(o) }
                self?.closeObserver = nil
                self?.window = nil
            }
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
