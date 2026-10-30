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

struct AgentLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var agents = AgentSessionStore.shared

    var body: some View {
        let side = max(0, vm.effectiveClosedNotchHeight - 12)
        let state: AgentSessionState = agents.needsAttention ? .needsAttention : .working
        HStack {
            AgentStatusGlyph(state: state, size: side * 0.8)
                .frame(width: side, height: side)
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)
            Text("\(agents.activeCount)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(state.tint)
                .frame(width: side, height: side)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

struct AgentBannerView: View {
    @EnvironmentObject var vm: BoringViewModel
    let banner: AgentBanner

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                AgentStatusGlyph(state: banner.state, size: 14)
                Text(banner.project)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: 220, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            Text(banner.state.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(banner.state.tint)
                .lineLimit(1)
                .frame(width: 90, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

struct AgentSessionsView: View {
    @ObservedObject var agents = AgentSessionStore.shared

    var body: some View {
        Group {
            if agents.sessions.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    header
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 4) {
                            ForEach(agents.sortedSessions) { session in
                                AgentSessionRow(session: session)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 4)
    }

    private var header: some View {
        HStack {
            Text("Claude Code")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.gray)
            Spacer()
            if agents.sessions.contains(where: { [.done, .failed, .idle].contains($0.state) }) {
                Button("Clear finished") { withAnimation(.smooth) { agents.clearFinished() } }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
        .padding(.horizontal, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.title2)
                .foregroundStyle(AgentSessionState.working.tint)
            Text("No Claude Code sessions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Install the Nubrix hooks to see sessions here.")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AgentSessionRow: View {
    let session: AgentSession
    @ObservedObject var agents = AgentSessionStore.shared
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            AgentStatusGlyph(state: session.state, size: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.project)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(session.state.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(session.state.tint)
                }
                if let detail = session.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            if hovering && session.state != .working && session.state != .needsAttention {
                Button {
                    withAnimation(.smooth) { agents.remove(session.id) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(Self.age(from: session.updatedAt, to: context.date))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hovering ? 0.1 : 0.06)))
        .onHover { hovering = $0 }
        .help(session.cwd)
    }

    private static func age(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }
}
