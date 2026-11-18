import SwiftUI
import AppKit

struct VitrinMenuItem {
    let title: String
    let action: () -> Void
}

/// Drag session source for every Vitrin drag. It is long-lived so a drag survives the notch closing
/// (and tearing down the card view) mid-drag.
@MainActor
final class VitrinDragSource: NSObject, NSDraggingSource {
    static let shared = VitrinDragSource()

    private(set) var isDragging = false
    fileprivate weak var originView: VitrinDragNSView?

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        MainActor.assumeIsolated { isDragging = true }
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        MainActor.assumeIsolated {
            isDragging = false
            originView?.recheckHover()
            originView = nil
        }
    }
}

/// Transparent overlay that owns the mouse for one Vitrin card. SwiftUI's `onDrag`, tap and context menu
/// are unreliable together on macOS and fight the notch's pan gesture, so the drag is started from AppKit.
struct VitrinDragSurface: NSViewRepresentable {
    let item: ClipItem
    var pinRect: (CGSize) -> CGRect
    var onClick: () -> Void
    var onPin: () -> Void
    var onHover: (Bool) -> Void
    var menuItems: () -> [VitrinMenuItem?]

    func makeNSView(context: Context) -> VitrinDragNSView {
        let view = VitrinDragNSView()
        update(view)
        return view
    }

    func updateNSView(_ view: VitrinDragNSView, context: Context) {
        update(view)
    }

    private func update(_ view: VitrinDragNSView) {
        view.item = item
        view.pinRect = pinRect
        view.onClick = onClick
        view.onPin = onPin
        view.onHover = onHover
        view.menuItems = menuItems
    }
}

final class VitrinDragNSView: NSView {
    var item: ClipItem?
    var pinRect: (CGSize) -> CGRect = { _ in .zero }
    var onClick: () -> Void = {}
    var onPin: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    var menuItems: () -> [VitrinMenuItem?] = { [] }

    private var mouseDownEvent: NSEvent?
    private var mouseDownPoint: NSPoint = .zero
    private var dragStarted = false
    private var hovering = false

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { setHovering(true) }
    override func mouseExited(with event: NSEvent) { setHovering(false) }

    private func setHovering(_ value: Bool) {
        guard hovering != value else { return }
        hovering = value
        onHover(value)
    }

    @MainActor func recheckHover() {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHovering(bounds.contains(point))
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            if let menu = menu(for: event) {
                NSMenu.popUpContextMenu(menu, with: event, for: self)
            }
            return
        }
        mouseDownEvent = event
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        dragStarted = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted, let downEvent = mouseDownEvent, let item else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y) > 3 else { return }
        dragStarted = true
        MainActor.assumeIsolated {
            guard let writer = ClipStore.shared.dragPasteboardItem(for: item) else { return }
            let draggingItem = NSDraggingItem(pasteboardWriter: writer)
            draggingItem.setDraggingFrame(bounds, contents: dragImage(for: item))
            VitrinDragSource.shared.originView = self
            beginDraggingSession(with: [draggingItem], event: downEvent, source: VitrinDragSource.shared)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard mouseDownEvent != nil, !dragStarted else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        if pinRect(bounds.size).contains(point) {
            onPin()
        } else {
            onClick()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let entries = menuItems()
        guard !entries.isEmpty else { return nil }
        let menu = NSMenu()
        for entry in entries {
            guard let entry else {
                menu.addItem(.separator())
                continue
            }
            let holder = VitrinMenuAction(entry.action)
            let menuItem = NSMenuItem(title: entry.title, action: #selector(VitrinMenuAction.run), keyEquivalent: "")
            menuItem.target = holder
            menuItem.representedObject = holder
            menu.addItem(menuItem)
        }
        return menu
    }

    @MainActor
    private func dragImage(for item: ClipItem) -> NSImage {
        let size = bounds.size
        let renderer = ImageRenderer(content: VitrinDragPreview(item: item).frame(width: size.width, height: size.height))
        renderer.scale = window?.backingScaleFactor ?? 2
        if let image = renderer.nsImage { return image }
        let fallback = NSImage(systemSymbolName: item.kind == .image ? "photo" : "doc.text", accessibilityDescription: nil) ?? NSImage(size: size)
        return fallback
    }
}

private final class VitrinMenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() { handler() }
}

private struct VitrinDragPreview: View {
    let item: ClipItem

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: VitrinMetrics.cornerRadius, style: .continuous)
    }

    var body: some View {
        switch item.kind {
        case .image: imagePreview
        case .text: textPreview
        case .link: linkPreview
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let thumbnail = ClipStore.shared.cachedThumbnail(for: item) {
            Color.clear
                .overlay {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(shape)
        } else {
            Image(systemName: "photo")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(shape.fill(Color(white: 0.12)))
        }
    }

    private var textPreview: some View {
        Text(item.previewOrEmpty)
            .font(.system(size: 11))
            .foregroundStyle(.white)
            .lineLimit(4)
            .multilineTextAlignment(.leading)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(shape.fill(Color(white: 0.12)))
    }

    private var linkPreview: some View {
        HStack(spacing: 5) {
            Image(systemName: "link")
            Text(LinkParts(item.previewOrEmpty).host)
                .lineLimit(1)
        }
        .font(.system(size: 11))
        .foregroundStyle(.white)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(Color(white: 0.12)))
    }
}
