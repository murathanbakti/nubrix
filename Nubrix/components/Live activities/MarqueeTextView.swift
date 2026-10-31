//
//  MarqueeTextView.swift
//  Nubrix
//
//  Created by Richard Kunkli on 08/08/2024.
//

import SwiftUI

final class MarqueeLayerView: NSView {
    private static let gap: CGFloat = 20
    private let scroller = CALayer()
    private let primary = CATextLayer()
    private let secondary = CATextLayer()
    private var text = ""
    private var font = NSFont.preferredFont(forTextStyle: .body)
    private var color = NSColor.white
    private var minDuration: Double = 3
    private var frameWidth: CGFloat = 200
    private var textWidth: CGFloat = 0
    private var overflows = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(scroller)
        for textLayer in [primary, secondary] {
            textLayer.isWrapped = false
            textLayer.truncationMode = .none
            textLayer.alignmentMode = .left
            scroller.addSublayer(textLayer)
        }
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(text: String, font: NSFont, color: NSColor, minDuration: Double, frameWidth: CGFloat) {
        let changed = text != self.text || font != self.font || color != self.color
            || minDuration != self.minDuration || frameWidth != self.frameWidth
        guard changed else { return }
        self.text = text
        self.font = font
        self.color = color
        self.minDuration = minDuration
        self.frameWidth = frameWidth
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
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        textWidth = ceil(attributed.size().width)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        overflows = textWidth + 10 > frameWidth && !text.isEmpty
        let step = textWidth + Self.gap

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scroller.removeAllAnimations()
        scroller.frame = CGRect(x: 0, y: 0, width: overflows ? textWidth * 2 + Self.gap : textWidth, height: lineHeight)
        for (index, textLayer) in [primary, secondary].enumerated() {
            textLayer.contentsScale = scale
            textLayer.string = attributed
            textLayer.frame = CGRect(x: CGFloat(index) * step, y: 0, width: textWidth, height: lineHeight)
            textLayer.isHidden = index == 1 && !overflows
        }
        CATransaction.commit()

        guard overflows, window != nil else { return }
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = scroller.position.x
        slide.toValue = scroller.position.x - step
        slide.duration = Double(textWidth + 10) / 30
        slide.beginTime = scroller.convertTime(CACurrentMediaTime(), from: nil) + minDuration
        slide.fillMode = .backwards
        slide.repeatCount = .infinity
        slide.isRemovedOnCompletion = false
        slide.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        scroller.add(slide, forKey: "marquee")
    }
}

struct MarqueeLayerRepresentable: NSViewRepresentable {
    let text: String
    let font: NSFont
    let color: NSColor
    let minDuration: Double
    let frameWidth: CGFloat

    func makeNSView(context: Context) -> MarqueeLayerView {
        MarqueeLayerView()
    }

    func updateNSView(_ nsView: MarqueeLayerView, context: Context) {
        nsView.update(text: text, font: font, color: color, minDuration: minDuration, frameWidth: frameWidth)
    }
}

struct MarqueeText: View {
    @Binding var text: String
    let font: Font
    let nsFont: NSFont.TextStyle
    let weight: NSFont.Weight?
    let textColor: Color
    let backgroundColor: Color
    let minDuration: Double
    let frameWidth: CGFloat

    init(_ text: Binding<String>, font: Font = .body, nsFont: NSFont.TextStyle = .body, weight: NSFont.Weight? = nil, textColor: Color = .primary, backgroundColor: Color = .clear, minDuration: Double = 3.0, frameWidth: CGFloat = 200) {
        _text = text
        self.font = font
        self.nsFont = nsFont
        self.weight = weight
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.minDuration = minDuration
        self.frameWidth = frameWidth
    }

    private var resolvedFont: NSFont {
        let base = NSFont.preferredFont(forTextStyle: nsFont)
        guard let weight else { return base }
        return NSFont.systemFont(ofSize: base.pointSize, weight: weight)
    }

    var body: some View {
        MarqueeLayerRepresentable(
            text: text,
            font: resolvedFont,
            color: NSColor(textColor),
            minDuration: minDuration,
            frameWidth: frameWidth
        )
        .frame(width: frameWidth, height: NSFont.preferredFont(forTextStyle: nsFont).pointSize * 1.3)
        .background(backgroundColor)
    }
}
