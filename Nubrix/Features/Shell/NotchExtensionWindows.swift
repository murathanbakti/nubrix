import AppKit
import Combine
import Defaults
import SwiftUI

extension Notification.Name {
    static let notchExtensionRequestNotchClose = Notification.Name("dev.nubrix.notchExtension.requestNotchClose")
}

final class NotchCloseRequest {
    var didClose = false
}

private struct NotchExtensionDismissKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var notchExtensionDismiss: @MainActor () -> Void {
        get { self[NotchExtensionDismissKey.self] }
        set { self[NotchExtensionDismissKey.self] = newValue }
    }
}

extension NSWindow {
    func bindSharingTypeToScreenRecordingPreference() -> AnyCancellable {
        sharingType = Defaults[.hideFromScreenRecording] ? .none : .readWrite
        return Defaults.publisher(.hideFromScreenRecording)
            .sink { [weak self] change in
                self?.sharingType = change.newValue ? .none : .readWrite
            }
    }
}

enum NotchExtensionWindowLevel {
    static let level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
    static let behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
}

final class NotchTransitionWindow: NSPanel {
    private var sharingObserver: AnyCancellable?

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        level = NotchExtensionWindowLevel.level
        collectionBehavior = NotchExtensionWindowLevel.behavior
        sharingObserver = bindSharingTypeToScreenRecordingPreference()
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class NotchExtensionPanel: NSPanel {
    private var sharingObserver: AnyCancellable?
    var draggable = false
    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var isDragging = false

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        isMovable = false
        level = NotchExtensionWindowLevel.level
        collectionBehavior = NotchExtensionWindowLevel.behavior
        sharingObserver = bindSharingTypeToScreenRecordingPreference()
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            if !isKeyWindow { makeKey() }
            if event.type == .leftMouseDown {
                dragStartMouse = NSEvent.mouseLocation
                dragStartOrigin = frame.origin
                isDragging = false
            }
            super.sendEvent(event)
        case .leftMouseDragged where draggable:
            let mouse = NSEvent.mouseLocation
            if !isDragging {
                guard hypot(mouse.x - dragStartMouse.x, mouse.y - dragStartMouse.y) > 4 else {
                    super.sendEvent(event)
                    return
                }
                isDragging = true
                cancelPressedControls()
            }
            var origin = NSPoint(x: dragStartOrigin.x + mouse.x - dragStartMouse.x, y: dragStartOrigin.y + mouse.y - dragStartMouse.y)
            if let screen = screen ?? NSScreen.main {
                origin.y = min(origin.y, screen.frame.maxY - frame.height)
            }
            setFrameOrigin(origin)
        case .leftMouseUp where isDragging:
            isDragging = false
        default:
            super.sendEvent(event)
        }
    }

    private func cancelPressedControls() {
        guard let up = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: NSPoint(x: -10_000, y: -10_000),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ) else { return }
        super.sendEvent(up)
    }
}

@MainActor
final class NotchExtensionPanelModel: ObservableObject {
    @Published var contentVisible = false
    let detached: Bool
    let notchHeight: CGFloat

    init(detached: Bool, notchHeight: CGFloat) {
        self.detached = detached
        self.notchHeight = notchHeight
    }
}

struct NotchExtensionPanelView: View {
    @ObservedObject var model: NotchExtensionPanelModel
    let content: AnyView
    let dismiss: @MainActor () -> Void
    @ObservedObject private var themeStore = ThemeStore.shared

    private var theme: NubrixTheme { themeStore.appliesToExtensions ? themeStore.current : .classic }

    var body: some View {
        Group {
            if model.detached {
                detached
            } else {
                attached
            }
        }
        .environment(\.notchExtensionDismiss, dismiss)
        .nubrixTheme(theme)
    }

    private var detached: some View {
        let shape = RoundedRectangle(cornerRadius: NotchExtensionMetrics.detachedCornerRadius, style: .continuous)
        return ZStack {
            ThemeBackground(theme: theme, shape: shape)
            content
                .opacity(model.contentVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.18), value: model.contentVisible)
        }
        .clipShape(shape)
    }

    private var attached: some View {
        ZStack(alignment: .top) {
            ThemeBackground(
                theme: theme,
                shape: NotchShape(
                    topCornerRadius: NotchExtensionMetrics.attachedTopRadius,
                    bottomCornerRadius: NotchExtensionMetrics.attachedBottomRadius
                )
            )
            content
                .padding(.top, model.notchHeight)
                .padding(.horizontal, NotchExtensionMetrics.attachedTopRadius)
                .opacity(model.contentVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.22), value: model.contentVisible)
        }
    }
}
