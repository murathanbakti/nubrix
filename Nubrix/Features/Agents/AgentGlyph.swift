import AppKit
import SwiftUI

final class AgentAnimatedGlyphView: NSView {
    enum Mode: Equatable {
        case spinner
        case pulse(symbol: String)
    }

    private let shape = CAShapeLayer()
    private let icon = CALayer()
    var mode: Mode = .spinner { didSet { if mode != oldValue { rebuild() } } }
    var color: NSColor = .orange { didSet { if color != oldValue { rebuild() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(shape)
        layer?.addSublayer(icon)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        rebuild()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        rebuild()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        rebuild()
    }

    private func rebuild() {
        let side = min(bounds.width, bounds.height)
        guard side > 0 else { return }
        let scale = window?.backingScaleFactor ?? 2
        let frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.removeAllAnimations()
        icon.removeAllAnimations()
        switch mode {
        case .spinner:
            icon.isHidden = true
            shape.isHidden = false
            let lineWidth = max(1.5, side / 7)
            let inset = lineWidth / 2 + side * 0.08
            shape.bounds = CGRect(origin: .zero, size: frame.size)
            shape.position = CGPoint(x: frame.midX, y: frame.midY)
            shape.path = CGPath(ellipseIn: shape.bounds.insetBy(dx: inset, dy: inset), transform: nil)
            shape.fillColor = nil
            shape.strokeColor = color.cgColor
            shape.lineWidth = lineWidth
            shape.lineCap = .round
            shape.strokeStart = 0.15
            shape.strokeEnd = 0.85
            shape.contentsScale = scale
        case .pulse(let symbol):
            shape.isHidden = true
            icon.isHidden = false
            icon.frame = frame
            icon.contentsScale = scale
            icon.contentsGravity = .resizeAspect
            let configuration = NSImage.SymbolConfiguration(pointSize: side, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) {
                icon.contents = image.layerContents(forContentsScale: scale)
            }
        }
        CATransaction.commit()
        guard window != nil else { return }
        switch mode {
        case .spinner:
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = Double.pi * 2
            rotation.duration = 0.9
            rotation.repeatCount = .infinity
            rotation.isRemovedOnCompletion = false
            shape.add(rotation, forKey: "spin")
        case .pulse:
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0.35
            fade.duration = 0.8
            fade.autoreverses = true
            fade.repeatCount = .infinity
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fade.isRemovedOnCompletion = false
            icon.add(fade, forKey: "pulse")
        }
    }
}

struct AgentAnimatedGlyph: NSViewRepresentable {
    let mode: AgentAnimatedGlyphView.Mode
    let color: Color

    func makeNSView(context: Context) -> AgentAnimatedGlyphView {
        let view = AgentAnimatedGlyphView()
        view.mode = mode
        view.color = NSColor(color)
        return view
    }

    func updateNSView(_ view: AgentAnimatedGlyphView, context: Context) {
        view.mode = mode
        view.color = NSColor(color)
    }
}

struct AgentStatusGlyph: View {
    let state: AgentSessionState
    var size: CGFloat = 14

    var body: some View {
        Group {
            switch state {
            case .working:
                AgentAnimatedGlyph(mode: .spinner, color: state.tint)
            case .needsAttention:
                AgentAnimatedGlyph(mode: .pulse(symbol: "exclamationmark.circle.fill"), color: state.tint)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .foregroundStyle(state.tint)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .resizable()
                    .foregroundStyle(state.tint)
            case .idle:
                Image(systemName: "moon.zzz.fill")
                    .resizable()
                    .foregroundStyle(state.tint)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: size, height: size)
    }
}
