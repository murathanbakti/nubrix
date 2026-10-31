import AppKit
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
                        .foregroundStyle(.gray)
                        .frame(width: 12, height: 12)
                }
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.72))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.09)))
        }
    }
}

struct AgentContextBar: View {
    let percent: Double
    var width: CGFloat = 46

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.14))
            Capsule()
                .fill(AgentMeter.color(for: percent))
                .frame(width: max(3, width * min(1, max(0, percent / 100))))
        }
        .frame(width: width, height: 4)
    }
}

struct AgentSessionRowBody: View {
    let session: AgentSession
    var hovering = false
    var onRemove: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            AgentStatusGlyph(state: session.state, size: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.project)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let branch = session.branch, !branch.isEmpty {
                        Text(branch)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(white: 0.6))
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
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                AgentSourceChip(source: session.source)
                if session.contextUsedPercent != nil || session.costUSD != nil {
                    HStack(spacing: 6) {
                        if let percent = session.contextUsedPercent {
                            AgentContextBar(percent: percent)
                        }
                        if let cost = session.costUSD {
                            Text(AgentMeter.cost(cost))
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.gray)
                        }
                    }
                    .help(Self.meterHelp(session))
                }
            }
            if hovering && session.state != .working && session.state != .needsAttention {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
                .frame(width: 26)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(Self.age(from: session.updatedAt, to: context.date))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.gray)
                        .frame(width: 26, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hovering ? 0.1 : 0.06)))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    static func meterHelp(_ session: AgentSession) -> String {
        var parts: [String] = []
        if let percent = session.contextUsedPercent {
            var text = "Context \(Int(percent.rounded()))%"
            if let size = session.contextWindowSize { text += " of \(size >= 1_000_000 ? "\(size / 1_000_000)M" : "\(size / 1000)k")" }
            parts.append(text)
        }
        if let model = session.modelName { parts.append(model) }
        if let cost = session.costUSD { parts.append(AgentMeter.cost(cost)) }
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
    let limits: AgentRateLimits?
    var clearVisible = false
    var onClear: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Text("Claude Code")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.gray)
            Spacer()
            if let limits = limits?.current() {
                if let percent = limits.fiveHourPercent {
                    meter("5h", percent: percent, reset: limits.fiveHourResetsAt)
                }
                if let percent = limits.sevenDayPercent, percent >= 80 {
                    meter("7d", percent: percent, reset: nil)
                }
            }
            if clearVisible {
                Button("Clear finished", action: onClear)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
        .padding(.horizontal, 4)
    }

    private func meter(_ title: String, percent: Double, reset: Date?) -> some View {
        HStack(spacing: 5) {
            Circle().fill(AgentMeter.color(for: percent)).frame(width: 6, height: 6)
            Text("\(title): \(Int(percent.rounded()))%" + (reset.map { " · resets \(AgentMeter.resetTime($0))" } ?? ""))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Color(white: 0.7))
        }
    }
}

struct AgentPermissionCard: View {
    let prompt: AgentPermissionPrompt
    let title: String
    let position: Int
    let total: Int
    let sourceName: String?
    var showsTitle = true
    var onAllow: () -> Void = {}
    var onDeny: () -> Void = {}
    var onOpen: () -> Void = {}

    @State private var armed = false
    @State private var expanded = false

    private var payload: AgentPermissionPayload { prompt.payload }
    private var risky: Bool { !payload.risks.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            toolRow
            commandBox
            if risky { riskRow }
            buttonRow
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            AgentSourceChip(source: payload.source)
            if showsTitle {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if total > 1 {
                Text("\(position) of \(total)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.orange)
            }
        }
    }

    private var toolRow: some View {
        HStack(spacing: 6) {
            Text(payload.toolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.orange.opacity(0.18)))
            if let note = payload.note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
        }
    }

    private var commandColor: Color {
        risky ? Color(red: 1, green: 0.62, blue: 0.6) : Color(white: 0.92)
    }

    private var commandBox: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        return Text(payload.summary)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(commandColor)
            .lineLimit(expanded ? 14 : 3)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(shape.fill(risky ? Color.red.opacity(0.14) : Color.white.opacity(0.07)))
            .overlay(shape.stroke(risky ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { expanded.toggle() }
            .help(payload.summary)
    }

    private var riskRow: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text(payload.risks.joined(separator: " · "))
                .font(.system(size: 11, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.4))
    }

    private var openLabel: String {
        sourceName.map { "Open in \($0)" } ?? "Open in Claude"
    }

    private var buttonRow: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                Text(openLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.65))
            }
            .buttonStyle(.plain)
            Spacer()
            actionButton("Deny", fill: Color.white.opacity(0.14), text: .white, action: onDeny)
            allowButton
        }
    }

    @ViewBuilder
    private var allowButton: some View {
        if risky && !armed {
            actionButton("Allow", fill: Color.red.opacity(0.28), text: Color(red: 1, green: 0.55, blue: 0.52)) { armed = true }
        } else if risky {
            actionButton("Allow anyway", fill: Color(red: 0.85, green: 0.2, blue: 0.2), text: .white, action: onAllow)
        } else {
            actionButton("Allow", fill: Color(red: 0.2, green: 0.68, blue: 0.38), text: .white, action: onAllow)
        }
    }

    private func actionButton(_ label: String, fill: Color, text: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(text)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
    }
}
