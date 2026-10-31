import AppKit
import SwiftUI

final class NotchHoverTrackingView: NSView {
    var onChange: (Bool) -> Void = { _ in }
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(next)
        area = next
        if let window {
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            onChange(bounds.contains(point))
        }
    }

    override func mouseEntered(with event: NSEvent) { onChange(true) }
    override func mouseExited(with event: NSEvent) { onChange(false) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct NotchHoverTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NotchHoverTrackingView {
        let view = NotchHoverTrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: NotchHoverTrackingView, context: Context) {
        view.onChange = onChange
    }
}

extension View {
    func notchHover(_ onChange: @escaping (Bool) -> Void) -> some View {
        background(NotchHoverTracker(onChange: onChange))
    }
}
