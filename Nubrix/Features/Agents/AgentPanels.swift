import AppKit
import Defaults
import SwiftUI

enum AgentMeter {
    static func color(for percent: Double) -> Color {
        if percent > 85 { return .red }
        if percent >= 60 { return .orange }
        return .green
    }

    static func cost(_ value: Double) -> String {
        value < 10 ? String(format: "$%.2f", value) : String(format: "$%.0f", value)
    }

    static func resetTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

struct AgentSourceChip: View {
    @Environment(\.nubrixPalette) private var palette
    let source: AgentSourceInfo

    var body: some View {
        if let label = source.label {
            HStack(spacing: 4) {
                if let icon = AgentAppActivator.icon(bundleID: source.activationBundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: source.entrypoint == "claude-desktop" ? "macwindow" : "terminal")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                        .frame(width: 12, height: 12)
                }
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.foreground.opacity(0.72))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(palette.foreground.opacity(0.09)))
        }
    }
}

struct AgentContextBar: View {
    @Environment(\.nubrixPalette) private var palette
    let percent: Double
    var width: CGFloat = 46

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(palette.foreground.opacity(0.14))
            Capsule()
                .fill(AgentMeter.color(for: percent))
                .frame(width: max(3, width * min(1, max(0, percent / 100))))
        }
        .frame(width: width, height: 4)
    }
}

struct AgentSessionRowBody: View {
    @Environment(\.nubrixPalette) private var palette
    let session: AgentSession
    var hovering = false
    var pullRequest: GitHubPR? = nil
    var onRemove: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            AgentStatusGlyph(state: session.state, size: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.project)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                        .lineLimit(1)
                    if let branch = session.branch, !branch.isEmpty {
                        Text(branch)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(palette.foreground.opacity(0.6))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text(session.state.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(session.state.tint)
                        .fixedSize()
                }
                if let detail = session.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    if let pullRequest { GitHubPRChip(pr: pullRequest) }
                    AgentSourceChip(source: session.source)
                }
                if session.contextUsedPercent != nil || session.sessionTokens > 0 {
                    HStack(spacing: 5) {
                        if let percent = session.contextUsedPercent {
                            AgentContextBar(percent: percent)
                            Text("\(Int(percent.rounded()))%")
                                .font(.system(size: 10, weight: .medium).monospacedDigit())
                                .foregroundStyle(palette.foreground.opacity(0.72))
                        }
                        if session.sessionTokens > 0 {
                            Text(AgentUsageFormat.tokens(session.sessionTokens))
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(palette.secondary)
                        }
                    }
                    .help(Self.meterHelp(session))
                }
            }
            if hovering && session.state != .working && session.state != .needsAttention {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 26)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(Self.age(from: session.updatedAt, to: context.date))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(palette.secondary)
                        .frame(width: 26, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(palette.foreground.opacity(hovering ? 0.1 : 0.06)))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    static func meterHelp(_ session: AgentSession) -> String {
        var parts: [String] = []
        if let percent = session.contextUsedPercent {
            var text = "Context \(Int(percent.rounded()))%"
            if let tokens = session.contextTokens, let window = session.contextWindow {
                text += " (\(AgentUsageFormat.tokens(tokens)) of \(AgentUsageFormat.window(window)))"
            } else if let window = session.contextWindow {
                text += " of \(AgentUsageFormat.window(window))"
            }
            parts.append(text)
        }
        if let model = session.displayModel { parts.append(model) }
        if session.sessionTokens > 0 {
            parts.append("\(AgentUsageFormat.tokens(session.sessionTokens)) tokens this session (cache reads not counted)")
        }
        if let cost = session.displayCost {
            parts.append(cost.estimated ? "~\(AgentMeter.cost(cost.value)) estimated" : AgentMeter.cost(cost.value))
        }
        return parts.joined(separator: " · ")
    }

    static func age(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }
}

struct AgentUsageHeader: View {
    @Environment(\.nubrixPalette) private var palette
    let today: AgentDailyUsage?
    let summary: ClaudeUsageSummary?
    var now = Date()
    var clearVisible = false
    var infoActive = false
    var onInfo: () -> Void = {}
    var onClear: () -> Void = {}
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 10) {
            Text(Self.todayText(today))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(palette.foreground.opacity(0.7))
                .lineLimit(1)
                .layoutPriority(-1)
                .help("Tokens are input, output and cache writes counted from Claude Code transcripts since midnight; cache reads are not counted. Cost is an estimate from list prices.")
            Spacer(minLength: 8)
            if let summary, summary.hasOfficial {
                HStack(spacing: 10) {
                    if summary.fiveHour.source == .official, let percent = summary.fiveHour.percent {
                        meter(ClaudeUsageText.fiveHourTitle(summary.fiveHour, locale: locale), percent: percent,
                              reset: summary.fiveHour.resetsAt, didReset: summary.fiveHour.didReset)
                    }
                    if summary.sevenDay.source == .official, let percent = summary.sevenDay.percent {
                        meter(ClaudeUsageText.sevenDayTitle(summary.sevenDay, locale: locale), percent: percent,
                              reset: summary.sevenDay.resetsAt, didReset: summary.sevenDay.didReset)
                    }
                    if let scoped = summary.primaryScoped, scoped.percent > 0 {
                        meter(scoped.name, percent: scoped.percent, reset: nil, didReset: scoped.didReset, showsBar: false)
                    }
                }
                .help(ClaudeUsageText.tooltip(summary, now: now, locale: locale))
            }
            if clearVisible {
                Button("Clear finished", action: onClear)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
            }
            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(infoActive ? palette.foreground : palette.secondary)
            }
            .buttonStyle(.plain)
            .help("Connection status")
        }
        .padding(.horizontal, 4)
    }

    static func todayText(_ today: AgentDailyUsage?) -> String {
        guard let today, today.tokens > 0 else { return "Claude Code" }
        var text = "Today · \(AgentUsageFormat.tokens(today.tokens)) tokens"
        if today.costUSD > 0 { text += " · ~\(AgentMeter.cost(today.costUSD))" }
        return text
    }

    private func meter(_ title: String, percent: Double, reset: Date?, didReset: Bool, showsBar: Bool = true) -> some View {
        var text = "\(title) \(ClaudeUsageText.percent(percent, locale: locale))"
        if let short = ClaudeUsageText.shortReset(reset, didReset: didReset, now: now, locale: locale) {
            text += " · " + short
        }
        return HStack(spacing: 5) {
            if showsBar { AgentContextBar(percent: percent, width: 28) }
            Text(text)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(palette.foreground.opacity(0.7))
                .lineLimit(1)
                .fixedSize()
        }
    }
}

struct AgentPointerTracker: NSViewRepresentable {
    let onMove: (CGPoint) -> Void

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onMove = onMove
        return view
    }

    func updateNSView(_ view: TrackerView, context: Context) {
        view.onMove = onMove
    }

    final class TrackerView: NSView {
        var onMove: ((CGPoint) -> Void)?
        private var area: NSTrackingArea?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let next = NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(next)
            area = next
        }

        override func mouseMoved(with event: NSEvent) {
            onMove?(convert(event.locationInWindow, from: nil))
        }

        override func mouseEntered(with event: NSEvent) {
            onMove?(convert(event.locationInWindow, from: nil))
        }
    }
}

private struct AgentScrollHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct AgentBoundedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: AgentScrollHeightKey.self, value: proxy.size.height)
                })
        }
        .scrollIndicators(.visible)
        .frame(height: contentHeight > 0 ? min(contentHeight, maxHeight) : maxHeight)
        .onPreferenceChange(AgentScrollHeightKey.self) { contentHeight = $0 }
    }
}

struct AgentPermissionCard: View {
    @Environment(\.nubrixPalette) private var palette
    static let armDelay: Double = 0.7
    static let moveThreshold: CGFloat = 3
    static let confirmDelay: Double = 0.5

    let prompt: AgentPermissionPrompt
    let title: String
    let position: Int
    let total: Int
    let sourceName: String?
    var showsTitle = true
    var startsReady = false
    var onAllow: () -> Void = {}
    var onDeny: () -> Void = {}
    var onOpen: () -> Void = {}

    @Default(.claudeOpenSession) private var openSession
    @State private var confirming = false
    @State private var confirmArmed = true
    @State private var expanded = false
    @State private var dwellElapsed = false
    @State private var pointerMoved = false
    @State private var firstPoint: CGPoint?

    private var payload: AgentPermissionPayload { prompt.payload }
    private var risky: Bool { !payload.risks.isEmpty }
    private var ready: Bool { startsReady || (dwellElapsed && pointerMoved) }

    private static func isHardwareClick() -> Bool {
        guard let event = NSApp.currentEvent, event.type == .leftMouseUp, let cgEvent = event.cgEvent else { return false }
        return cgEvent.getIntegerValueField(.eventSourceStateID) == Int64(CGEventSourceStateID.hidSystemState.rawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            toolRow
            commandBox
            if let extra = payload.extraInput { extraBox(extra) }
            if let preview = payload.preview { previewBox(preview) }
            if risky { riskRow }
            buttonRow
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.foreground.opacity(0.06)))
        .background(AgentPointerTracker { point in track(point) })
        .task(id: prompt.id) {
            try? await Task.sleep(for: .seconds(Self.armDelay))
            guard !Task.isCancelled else { return }
            dwellElapsed = true
        }
        .task(id: confirming) {
            guard confirming else { return }
            try? await Task.sleep(for: .seconds(Self.confirmDelay))
            guard !Task.isCancelled else { return }
            confirmArmed = true
        }
    }

    private func track(_ point: CGPoint) {
        guard let first = firstPoint else {
            firstPoint = point
            return
        }
        if hypot(point.x - first.x, point.y - first.y) >= Self.moveThreshold { pointerMoved = true }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            AgentSourceChip(source: payload.source)
            if showsTitle {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if total > 1 {
                Text("\(position) of \(total)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(palette.warning)
            }
        }
    }

    private var toolRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(payload.toolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.warning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(palette.warning.opacity(0.18)))
                if payload.summaryLines > 1 || payload.summary.count > 160 {
                    Text(sizeLabel(lines: payload.summaryLines, characters: payload.summary.count))
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(palette.foreground.opacity(0.6))
                }
            }
            if let note = payload.note {
                Text("Claude's description: \(note)")
                    .font(.system(size: 10.5))
                    .italic()
                    .foregroundStyle(palette.foreground.opacity(0.55))
                    .lineLimit(2)
            }
        }
    }

    private func sizeLabel(lines: Int, characters: Int) -> String {
        "\(lines) \(lines == 1 ? "line" : "lines") · \(characters) chars"
    }

    private var commandColor: Color {
        risky ? palette.dangerText : palette.foreground.opacity(0.92)
    }

    private var commandBox: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        return AgentBoundedScroll(maxHeight: expanded ? 260 : 96) {
            Text(payload.summary)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(commandColor)
                .multilineTextAlignment(.leading)
                .padding(8)
        }
        .background(shape.fill(risky ? Color.red.opacity(0.14) : palette.foreground.opacity(0.07)))
        .overlay(shape.stroke(risky ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1))
        .clipShape(shape)
        .overlay(alignment: .topTrailing) { expandToggle }
    }

    private func extraBox(_ text: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        return VStack(alignment: .leading, spacing: 3) {
            Text("Extra tool input")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(palette.foreground.opacity(0.75))
            AgentBoundedScroll(maxHeight: 60) {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(commandColor)
                    .multilineTextAlignment(.leading)
                    .padding(8)
            }
            .background(shape.fill(Color.red.opacity(0.14)))
            .clipShape(shape)
        }
    }

    private var expandToggle: some View {
        Button { expanded.toggle() } label: {
            Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.foreground.opacity(0.7))
                .padding(4)
                .background(Circle().fill(Color.black.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .padding(4)
    }

    private func previewBox(_ preview: AgentPermissionPreview) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(preview.label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.foreground.opacity(0.75))
                Text(sizeLabel(lines: preview.lines, characters: preview.characters))
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(palette.foreground.opacity(0.55))
                if preview.truncated {
                    Text("truncated")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.danger)
                }
            }
            AgentBoundedScroll(maxHeight: expanded ? 260 : 110) {
                Text(Self.previewText(preview, palette: palette))
                    .font(.system(size: 11, design: .monospaced))
                    .multilineTextAlignment(.leading)
                    .padding(8)
            }
            .background(shape.fill(palette.foreground.opacity(0.05)))
            .clipShape(shape)
        }
    }

    static func previewText(_ preview: AgentPermissionPreview, palette: ThemePalette) -> AttributedString {
        let isDiff = preview.label.hasPrefix("Change")
        var result = AttributedString()
        let lines = preview.text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            var piece = AttributedString(index == lines.count - 1 ? String(line) : String(line) + "\n")
            if isDiff, line.hasPrefix("+ ") || line.hasPrefix("- ") {
                piece.foregroundColor = line.hasPrefix("+") ? palette.diffAdded : palette.diffRemoved
            } else if isDiff, line == "@@" {
                piece.foregroundColor = palette.foreground.opacity(0.5)
            } else {
                piece.foregroundColor = palette.foreground.opacity(0.88)
            }
            result.append(piece)
        }
        return result
    }

    private var riskRow: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text(payload.risks.joined(separator: " · "))
                .font(.system(size: 11, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(palette.danger)
    }

    private var openLabel: String {
        sourceName.map { "Open in \($0)" } ?? "Open in Claude"
    }

    private var buttonRow: some View {
        HStack(spacing: 8) {
            if openSession {
                Button(action: onOpen) {
                    Text(openLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.foreground.opacity(0.65))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if !ready, dwellElapsed {
                Text("Move the pointer here to enable Allow")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.foreground.opacity(0.55))
            }
            actionButton("Deny", fill: palette.foreground.opacity(0.14), text: palette.foreground, action: onDeny)
            allowButton
        }
    }

    @ViewBuilder
    private var allowButton: some View {
        if risky && !confirming {
            actionButton("Allow", fill: Color.red.opacity(0.28), text: palette.dangerButtonText, enabled: ready) {
                guard Self.isHardwareClick() else { return }
                confirmArmed = false
                confirming = true
            }
        } else if risky {
            actionButton("Allow anyway", fill: Color(red: 0.85, green: 0.2, blue: 0.2), text: .white, enabled: ready && confirmArmed) {
                guard Self.isHardwareClick() else { return }
                onAllow()
            }
        } else {
            actionButton("Allow", fill: Color(red: 0.2, green: 0.68, blue: 0.38), text: .white, enabled: ready) {
                guard Self.isHardwareClick() else { return }
                onAllow()
            }
        }
    }

    private func actionButton(_ label: String, fill: Color, text: Color, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(text)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }
}
