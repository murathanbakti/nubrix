//
//  PanGesture.swift
//  Nubrix
//
//  Created by Richard Kunkli on 21/08/2024.
//

import AppKit
import SwiftUI

enum PanDirection {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }
    var sign: CGFloat { (self == .right || self == .down) ? 1 : -1 }

    func signed(from translation: CGSize) -> CGFloat { (isHorizontal ? translation.width : translation.height) * sign }
    func signed(deltaX: CGFloat, deltaY: CGFloat) -> CGFloat { (isHorizontal ? deltaX : deltaY) * sign }
}

extension View {
    func panGesture(direction: PanDirection, threshold: CGFloat = 4, action: @escaping (CGFloat, NSEvent.Phase) -> Void) -> some View {
        self
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let s = direction.signed(from: value.translation)
                        guard s > 0, s.magnitude >= threshold else { return }
                        action(s.magnitude, .changed)
                    }
                    .onEnded { _ in action(0, .ended) }
            )
            .background(ScrollMonitor(direction: direction, threshold: threshold, action: action))
    }
}

private struct ScrollMonitor: NSViewRepresentable {
    let direction: PanDirection
    let threshold: CGFloat
    let action: (CGFloat, NSEvent.Phase) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.removeMonitor() }

    func makeCoordinator() -> Coordinator { 
        Coordinator(direction: direction, threshold: threshold, action: action) 
    }

    @MainActor final class Coordinator: NSObject {
        private let direction: PanDirection
        private let threshold: CGFloat
        private let action: (CGFloat, NSEvent.Phase) -> Void
        private var monitor: Any?
        private weak var hostView: NSView?
        private var blocked = false
        private var accumulated: CGFloat = 0
        private var active = false
            private var endTask: Task<Void, Never>?
        private let noiseThreshold: CGFloat = 0.2

        init(direction: PanDirection, threshold: CGFloat, action: @escaping (CGFloat, NSEvent.Phase) -> Void) {
            self.direction = direction
            self.threshold = threshold
            self.action = action
        }

        private func scheduleEndTimeout() {
            // Cancel any existing scheduled end and schedule a new one.
            endTask?.cancel()
            endTask = Task { @MainActor in
                // If no new scroll event arrives within this window, consider the gesture ended.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
            }
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            hostView = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self, weak view] event in
                guard let self = self, event.window === view?.window else { return event }
                self.handleScroll(event)
                return event
            }
        }

        func removeMonitor() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            accumulated = 0
            active = false
            blocked = false
            endTask?.cancel()
            endTask = nil
        }

        private func isBlocked(by event: NSEvent) -> Bool {
            guard let contentView = hostView?.window?.contentView else { return false }
            let point = contentView.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            var current: NSView? = contentView.hitTest(point)
            while let view = current {
                if let scrollView = view as? NSScrollView, canScroll(scrollView) { return true }
                current = view.superview
            }
            return containsScrollableView(contentView, windowPoint: event.locationInWindow)
        }

        private func containsScrollableView(_ view: NSView, windowPoint: NSPoint) -> Bool {
            for sub in view.subviews where !sub.isHidden {
                let local = sub.convert(windowPoint, from: nil)
                guard sub.bounds.contains(local) else { continue }
                if let scrollView = sub as? NSScrollView, canScroll(scrollView) { return true }
                if containsScrollableView(sub, windowPoint: windowPoint) { return true }
            }
            return false
        }

        private func canScroll(_ scrollView: NSScrollView) -> Bool {
            guard let document = scrollView.documentView else { return false }
            let visible = scrollView.documentVisibleRect
            let bounds = document.bounds
            let tolerance: CGFloat = 1
            let revealsLater = direction.sign < 0
            if direction.isHorizontal {
                return revealsLater ? visible.maxX < bounds.maxX - tolerance : visible.minX > bounds.minX + tolerance
            }
            if document.isFlipped {
                return revealsLater ? visible.maxY < bounds.maxY - tolerance : visible.minY > bounds.minY + tolerance
            }
            return revealsLater ? visible.minY > bounds.minY + tolerance : visible.maxY < bounds.maxY - tolerance
        }

        private func handleScroll(_ event: NSEvent) {
            let phase = event.phase
            let momentum = event.momentumPhase
            if phase.isEmpty && momentum.isEmpty {
                blocked = isBlocked(by: event)
            } else if phase.contains(.began) {
                blocked = isBlocked(by: event)
            }
            if blocked {
                accumulated = 0
                if momentum.contains(.ended) || momentum.contains(.cancelled) { blocked = false }
                return
            }

            if event.phase == .ended || event.momentumPhase == .ended {
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
                return
            }

            // Only consider scroll events that are primarily along the configured axis.
            let absDX = abs(event.scrollingDeltaX)
            let absDY = abs(event.scrollingDeltaY)
            // Require the movement along the gesture axis to be at least 1.5x the orthogonal axis.
            let axisDominanceFactor: CGFloat = 1.5
            let isAxisDominant: Bool = direction.isHorizontal ? (absDX >= axisDominanceFactor * absDY) : (absDY >= axisDominanceFactor * absDX)
            guard isAxisDominant else { return }

            // Scale non-precise (mouse wheel) scrolling deltas so they feel similar to
            // trackpad gestures.
            let raw = direction.signed(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
            let s = raw * scale
            guard s.magnitude > noiseThreshold else { return }
            accumulated = s > 0 ? accumulated + s : 0

            if !active && accumulated >= threshold {
                active = true
                action(accumulated.magnitude, .began)
            } else if active {
                action(accumulated.magnitude, .changed)
            }
            // Schedule a timeout to end the gesture if no further scroll events arrive.
            scheduleEndTimeout()
        }
    }
}
