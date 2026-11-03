import AppKit
import Defaults
import SwiftUI

@MainActor
enum FullDiskAccessGuide {
    private static var panel: NSPanel?
    private static var closeObserver: NSObjectProtocol?

    static func begin(origin: FDAOrigin = .settings) {
        let wasEnabled = Defaults[.systemNotificationsEnabled]
        Defaults[.systemNotificationsEnabled] = true
        let store = SystemNotificationStore.shared
        if !wasEnabled { store.settingChanged() }
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        Task { @MainActor in
            let status = await store.checkNow()
            guard status == .noAccess else { return }
            guard Defaults[.systemNotificationsEnabled] else { return }
            LaunchFlow().beginFDAGrant(origin: origin)
            openSettings()
            show()
        }
    }

    static func close() {
        panel?.close()
    }

    static func openSettings() {
        Permissions.client.openSystemSettings(.fullDiskAccess)
    }

    static func showReturn() {
        show()
    }

    private static func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let hosting = NSHostingView(rootView: FullDiskAccessGuideView(onClose: { close() }))
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
                SystemNotificationStore.shared.setFastRecheck(false)
                if let token = closeObserver { NotificationCenter.default.removeObserver(token) }
                closeObserver = nil
                Self.panel = nil
            }
        }
        Self.panel = panel
        SystemNotificationStore.shared.setFastRecheck(true)
        panel.orderFrontRegardless()
    }
}

struct FullDiskAccessGuideView: View {
    @ObservedObject var store = SystemNotificationStore.shared
    let onClose: () -> Void
    @State private var showRestart = false
    @State private var closing = false

    private var granted: Bool { store.status == .ready }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                Text("Allow Full Disk Access")
                    .font(.headline)
            }
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    step(1, "Drag Nubrix into the list")
                    step(2, "Turn on the switch next to Nubrix")
                    step(3, "Choose Quit & Reopen. Nubrix comes back here.")
                }
                Spacer(minLength: 0)
                dragTile
            }
            footer
            HStack {
                Button("Open System Settings") { FullDiskAccessGuide.openSettings() }
                Spacer()
                Button("Close") {
                    LaunchFlow().clearFDAPending()
                    onClose()
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .padding(.bottom, 14)
        .frame(width: 400, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
        .task {
            try? await Task.sleep(for: .seconds(20))
            if !Task.isCancelled { showRestart = true }
        }
        .onAppear { if granted { closeAfterGrant(delay: 4) } }
        .onChange(of: granted) { _, now in
            if now { closeAfterGrant(delay: 2) }
        }
    }

    private func closeAfterGrant(delay: Double) {
        LaunchFlow().clearFDAPending()
        guard !closing else { return }
        closing = true
        Task {
            try? await Task.sleep(for: .seconds(delay))
            onClose()
        }
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

    private var dragTile: some View {
        VStack(spacing: 2) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            Text("Nubrix")
                .font(.caption.weight(.medium))
            Text("Drag me")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
        .help("Drag Nubrix into the Full Disk Access list in System Settings")
    }

    @ViewBuilder
    private var footer: some View {
        if granted {
            Label {
                Text("Access granted. Notifications are on.")
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
                if showRestart {
                    Button("Granted already? Restart Nubrix") { ApplicationRelauncher.restart() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
    }
}
