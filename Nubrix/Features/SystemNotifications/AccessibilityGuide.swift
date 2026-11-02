import AppKit
import SwiftUI

@MainActor
enum AccessibilityGuide {
    private static var panel: NSPanel?
    private static var closeObserver: NSObjectProtocol?
    private static var resumeRecord: SystemNotificationRecord?
    private static var pollTask: Task<Void, Never>?
    private static let model = AccessibilityGuideModel()
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

    static func begin(resume record: SystemNotificationRecord?) {
        if let panel {
            if let record { resumeRecord = record }
            panel.orderFrontRegardless()
            return
        }
        resumeRecord = record
        Task { @MainActor in
            if await XPCHelperClient.shared.isAccessibilityAuthorized() {
                resume()
                return
            }
            if let panel {
                panel.orderFrontRegardless()
                return
            }
            openSettings()
            show()
        }
    }

    static func close() {
        panel?.close()
    }

    static func shutdown() {
        resumeRecord = nil
        pollTask?.cancel()
        pollTask = nil
        close()
    }

    static func openSettings() {
        if let settingsURL { NSWorkspace.shared.open(settingsURL) }
    }

    private static func resume() {
        let record = resumeRecord
        resumeRecord = nil
        guard NotificationReplyController.isEnabled else { return }
        if let record { NotificationReplyController.shared.openAndBegin(record: record) }
    }

    private static func startPolling() {
        pollTask?.cancel()
        model.granted = false
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                if await XPCHelperClient.shared.isAccessibilityAuthorized() {
                    if Task.isCancelled { return }
                    model.granted = true
                    try? await Task.sleep(for: .seconds(1.2))
                    if Task.isCancelled { return }
                    close()
                    resume()
                    return
                }
            }
        }
    }

    private static func show() {
        let hosting = NSHostingView(rootView: AccessibilityGuideView(model: model, onClose: { close() }))
        let fitting = hosting.fittingSize
        let size = NSSize(width: 400, height: max(fitting.height, 200))
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        panel.setContentSize(size)
        if let frame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 24, y: frame.minY + 24))
        }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { _ in
            Task { @MainActor in
                pollTask?.cancel()
                pollTask = nil
                if let token = closeObserver { NotificationCenter.default.removeObserver(token) }
                closeObserver = nil
                Self.panel = nil
            }
        }
        Self.panel = panel
        startPolling()
        panel.orderFrontRegardless()
    }
}

@MainActor
final class AccessibilityGuideModel: ObservableObject {
    @Published var granted = false
}

struct AccessibilityGuideView: View {
    @ObservedObject var model: AccessibilityGuideModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                Text("Allow Accessibility")
                    .font(.headline)
            }
            Text("Nubrix types your reply into the notification's own Reply box.")
                .font(.callout)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    step(1, "Find Nubrix in the list, or drag it in")
                    step(2, "Turn on the switch next to Nubrix")
                }
                Spacer(minLength: 0)
                AppDragTile(help: "Drag Nubrix into the Accessibility list in System Settings")
            }
            Text("Nubrix is already on? Select it, remove it with −, then drag it in again. macOS keeps the old switch after a different build of Nubrix is installed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            footer
            HStack {
                Button("Open System Settings") { AccessibilityGuide.openSettings() }
                Spacer()
                Button("Close") { onClose() }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .padding(.bottom, 14)
        .frame(width: 400, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(number).")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.granted {
            Label {
                Text("Access granted")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .font(.callout)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for access…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}
