import CoreGraphics
import Foundation
import SwiftUI

enum NotchExtensionMode: Equatable {
    case detached(size: CGSize)
    case attached(size: CGSize)

    var size: CGSize {
        switch self {
        case .detached(let size), .attached(let size): return size
        }
    }

    var isDetached: Bool {
        if case .detached = self { return true }
        return false
    }

    func resized(to size: CGSize) -> NotchExtensionMode {
        isDetached ? .detached(size: size) : .attached(size: size)
    }
}

enum NotchExtensionMetrics {
    static let detachedCornerRadius: CGFloat = 26
    static let detachedCenterFraction: CGFloat = 0.42
    static let attachedTopRadius: CGFloat = 20
    static let attachedBottomRadius: CGFloat = 26
    static let closedTopRadius: CGFloat = 6
    static let closedBottomRadius: CGFloat = 14
    static let openDuration: TimeInterval = 0.95
    static let closeDuration: TimeInterval = 0.7
    static let attachedOpenDuration: TimeInterval = 0.62
    static let attachedCloseDuration: TimeInterval = 0.4
}

struct NotchExtensionGeometry: Equatable {
    var screenSize: CGSize
    var notch: CGRect
    var target: CGRect
    var detached: Bool
    var canvas: CGRect

    static func make(
        screenSize: CGSize,
        visibleTopInset: CGFloat,
        visibleHeight: CGFloat,
        notchSize: CGSize,
        mode: NotchExtensionMode,
        targetOverride: CGRect? = nil
    ) -> NotchExtensionGeometry {
        let notch = CGRect(
            x: (screenSize.width - notchSize.width) / 2,
            y: 0,
            width: notchSize.width,
            height: notchSize.height
        )
        let size = mode.size
        var target: CGRect
        if mode.isDetached {
            let centerY = visibleTopInset + visibleHeight * NotchExtensionMetrics.detachedCenterFraction
            var y = centerY - size.height / 2
            y = max(y, visibleTopInset + 12)
            y = min(y, max(visibleTopInset + 12, screenSize.height - size.height - 12))
            target = CGRect(x: (screenSize.width - size.width) / 2, y: y, width: size.width, height: size.height)
        } else {
            target = CGRect(x: (screenSize.width - size.width) / 2, y: 0, width: size.width, height: size.height)
        }
        if let targetOverride { target = targetOverride }
        let padX: CGFloat = mode.isDetached ? 70 : 40
        let padBottom: CGFloat = mode.isDetached ? 70 : 40
        let minX = min(target.minX, notch.minX) - padX
        let maxX = max(target.maxX, notch.maxX) + padX
        let canvas = CGRect(x: minX, y: 0, width: maxX - minX, height: target.maxY + padBottom)
        return NotchExtensionGeometry(
            screenSize: screenSize,
            notch: notch,
            target: target,
            detached: mode.isDetached,
            canvas: canvas
        )
    }
}

struct NotchExtensionBlob {
    var rect: CGRect
    var radius: CGFloat
    var bridges: [Path]
}

struct NotchExtensionSheet {
    var rect: CGRect
    var topRadius: CGFloat
    var bottomRadius: CGFloat
}

enum NotchExtensionTimeline {
    static func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    static func pchip(_ keys: [(CGFloat, CGFloat)], _ x: CGFloat) -> CGFloat {
        guard let first = keys.first, let last = keys.last else { return 0 }
        if x <= first.0 { return first.1 }
        if x >= last.0 { return last.1 }
        let n = keys.count
        var d = [CGFloat](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            d[i] = (keys[i + 1].1 - keys[i].1) / (keys[i + 1].0 - keys[i].0)
        }
        var m = [CGFloat](repeating: 0, count: n)
        if n > 2 {
            for i in 1..<(n - 1) {
                if d[i - 1] * d[i] <= 0 {
                    m[i] = 0
                } else {
                    let h0 = keys[i].0 - keys[i - 1].0
                    let h1 = keys[i + 1].0 - keys[i].0
                    let w1 = 2 * h1 + h0
                    let w2 = h1 + 2 * h0
                    m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
                }
            }
        }
        var k = 0
        while k < n - 2 && x > keys[k + 1].0 { k += 1 }
        let h = keys[k + 1].0 - keys[k].0
        let t = (x - keys[k].0) / h
        let t2 = t * t
        let t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2
        return h00 * keys[k].1 + h10 * h * m[k] + h01 * keys[k + 1].1 + h11 * h * m[k + 1]
    }

    static func blob(_ rawU: CGFloat, _ g: NotchExtensionGeometry) -> NotchExtensionBlob {
        let u = min(1, max(0, rawU))
        let n = g.notch
        let t = g.target
        let nh = n.height
        let top: CGFloat
        let bottom: CGFloat
        let width: CGFloat
        let centerX: CGFloat
        let split: CGFloat = 0.58
        if u <= split {
            top = pchip([(0, nh - 14), (0.30, nh - 12), (0.46, nh + 4), (split, nh + 34)], u)
            bottom = pchip([(0, nh - 4), (0.30, nh + 46), (0.46, nh + 100), (split, nh + 132)], u)
            width = pchip([(0, n.width - 40), (0.30, n.width * 0.66), (0.46, n.width * 0.5), (split, n.width * 0.48)], u)
            centerX = n.midX
        } else {
            let f = pchip([(split, 0), (0.69, 0.25), (0.79, 0.62), (0.89, 0.92), (1, 1)], u)
            let s = pchip([(split, 0), (0.72, 0.18), (0.83, 0.62), (0.93, 0.95), (1, 1)], u)
            top = lerp(nh + 34, t.minY, f)
            bottom = lerp(nh + 132, t.maxY, f)
            width = lerp(n.width * 0.48, t.width, s)
            centerX = lerp(n.midX, t.midX, f)
        }
        let rect = CGRect(x: centerX - width / 2, y: top, width: width, height: max(2, bottom - top))
        let capsule = min(rect.width, rect.height) / 2
        let radius = min(capsule, lerp(capsule, NotchExtensionMetrics.detachedCornerRadius, smoothstep(0.6, 1, u)))
        let bridges = bridgePaths(u, g, drop: rect, radius: radius)
        return NotchExtensionBlob(rect: rect, radius: radius, bridges: bridges)
    }

    private static func bridgePaths(_ u: CGFloat, _ g: NotchExtensionGeometry, drop: CGRect, radius: CGFloat) -> [Path] {
        let cx = g.notch.midX
        let nh = g.notch.height
        let y0 = nh - 3
        let y1 = min(drop.minY + radius, drop.maxY - radius * 0.3)
        guard u < 0.64, drop.minY < nh + 60 else { return [] }
        let dropHalf = drop.width / 2
        let snap: CGFloat = 0.5
        if u < snap {
            guard drop.maxY > nh + 8, y1 > y0 + 6 else { return [] }
            let thin = smoothstep(0.30, snap, u)
            let waist = lerp(dropHalf, 3.5, pow(thin, 0.75))
            let flare = lerp(16, 9, thin)
            let bottom = lerp(dropHalf, waist + 14, thin)
            return [neck(cx: cx, y0: y0, y1: y1, top: waist + flare, waist: waist, bottom: bottom)]
        }
        let r = smoothstep(snap, 0.62, u)
        let tip = 24 * (1 - r)
        guard tip > 0.5 else { return [] }
        var upper = Path()
        let a: CGFloat = 12
        upper.move(to: CGPoint(x: cx - a, y: nh - 4))
        upper.addQuadCurve(to: CGPoint(x: cx, y: nh + tip), control: CGPoint(x: cx - 2.5, y: nh + tip * 0.35))
        upper.addQuadCurve(to: CGPoint(x: cx + a, y: nh - 4), control: CGPoint(x: cx + 2.5, y: nh + tip * 0.35))
        upper.closeSubpath()
        var lower = Path()
        let top = drop.minY
        lower.move(to: CGPoint(x: cx - a - 4, y: top + 6))
        lower.addQuadCurve(to: CGPoint(x: cx, y: top - tip * 0.8), control: CGPoint(x: cx - 2.5, y: top - tip * 0.25))
        lower.addQuadCurve(to: CGPoint(x: cx + a + 4, y: top + 6), control: CGPoint(x: cx + 2.5, y: top - tip * 0.25))
        lower.closeSubpath()
        return [upper, lower]
    }

    private static func neck(cx: CGFloat, y0: CGFloat, y1: CGFloat, top: CGFloat, waist: CGFloat, bottom: CGFloat) -> Path {
        let ym = (y0 + y1) / 2
        var path = Path()
        path.move(to: CGPoint(x: cx - top, y: y0))
        path.addCurve(
            to: CGPoint(x: cx - waist, y: ym),
            control1: CGPoint(x: cx - top + (top - waist) * 0.7, y: y0),
            control2: CGPoint(x: cx - waist, y: ym - (ym - y0) * 0.5)
        )
        path.addCurve(
            to: CGPoint(x: cx - bottom, y: y1),
            control1: CGPoint(x: cx - waist, y: ym + (y1 - ym) * 0.5),
            control2: CGPoint(x: cx - bottom + (bottom - waist) * 0.3, y: y1 - (y1 - ym) * 0.1)
        )
        path.addLine(to: CGPoint(x: cx + bottom, y: y1))
        path.addCurve(
            to: CGPoint(x: cx + waist, y: ym),
            control1: CGPoint(x: cx + bottom - (bottom - waist) * 0.3, y: y1 - (y1 - ym) * 0.1),
            control2: CGPoint(x: cx + waist, y: ym + (y1 - ym) * 0.5)
        )
        path.addCurve(
            to: CGPoint(x: cx + top, y: y0),
            control1: CGPoint(x: cx + waist, y: ym - (ym - y0) * 0.5),
            control2: CGPoint(x: cx + top - (top - waist) * 0.7, y: y0)
        )
        path.closeSubpath()
        return path
    }

    static func sheet(_ p: CGFloat, _ g: NotchExtensionGeometry) -> NotchExtensionSheet {
        let n = g.notch
        let t = g.target
        let width = max(n.width, lerp(n.width, t.width, p))
        let height = max(n.height, lerp(n.height, t.height, p))
        let q = min(1, max(0, p))
        return NotchExtensionSheet(
            rect: CGRect(x: g.screenSize.width / 2 - width / 2, y: 0, width: width, height: height),
            topRadius: lerp(NotchExtensionMetrics.closedTopRadius, NotchExtensionMetrics.attachedTopRadius, q),
            bottomRadius: lerp(NotchExtensionMetrics.closedBottomRadius, NotchExtensionMetrics.attachedBottomRadius, q)
        )
    }
}

struct NotchExtensionTransition {
    enum Direction { case opening, closing }

    var direction: Direction
    var start: Date
    var duration: TimeInterval
    var from: CGFloat
    var detached: Bool

    static func opening(detached: Bool, start: Date = Date()) -> NotchExtensionTransition {
        NotchExtensionTransition(
            direction: .opening,
            start: start,
            duration: detached ? NotchExtensionMetrics.openDuration : NotchExtensionMetrics.attachedOpenDuration,
            from: 0,
            detached: detached
        )
    }

    static func closing(detached: Bool, from: CGFloat, start: Date = Date()) -> NotchExtensionTransition {
        NotchExtensionTransition(
            direction: .closing,
            start: start,
            duration: (detached ? NotchExtensionMetrics.closeDuration : NotchExtensionMetrics.attachedCloseDuration) * Double(max(0.3, min(1, from))),
            from: min(1, max(0, from)),
            detached: detached
        )
    }

    func progress(at date: Date) -> CGFloat {
        let elapsed = max(0, date.timeIntervalSince(start))
        switch direction {
        case .opening:
            if detached { return CGFloat(min(1, elapsed / duration)) }
            if elapsed >= duration { return 1 }
            return Self.spring(elapsed)
        case .closing:
            let tau = CGFloat(min(1, elapsed / duration))
            let eased = detached ? tau : tau * tau * (3 - 2 * tau)
            return from * (1 - eased)
        }
    }

    static func spring(_ t: TimeInterval) -> CGFloat {
        let zeta = 0.78
        let omega = 15.0
        let wd = omega * (1 - zeta * zeta).squareRoot()
        let decay = exp(-zeta * omega * t)
        let value = 1 - decay * (cos(wd * t) + (zeta * omega / wd) * sin(wd * t))
        return CGFloat(value)
    }
}
