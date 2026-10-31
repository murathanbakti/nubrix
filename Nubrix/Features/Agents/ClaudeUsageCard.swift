import SwiftUI

struct ClaudeUsageCardContent: View {
    let summary: ClaudeUsageSummary
    let now: Date
    var width: CGFloat = 130
    var showsCost = true
    var note: String?
    let onOpen: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: onOpen) {
            ViewThatFits(in: .vertical) {
                cardBody(showsExtra: summary.highestScoped != nil || note != nil)
                cardBody(showsExtra: false)
            }
            .padding(10)
            .frame(width: width, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(ClaudeUsageText.tooltip(summary, now: now, locale: locale))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ClaudeUsageText.tooltip(summary, now: now, locale: locale))
    }

    private func cardBody(showsExtra: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AgentSessionState.working.tint)
                Text("Claude")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if summary.hasPlanData && summary.isPlanStale(now: now) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(white: 0.55))
                }
            }
            usageRow(title: ClaudeUsageText.fiveHourTitle(summary.fiveHour, locale: locale), row: summary.fiveHour, spark: false)
            usageRow(title: ClaudeUsageText.sevenDayTitle(summary.sevenDay, locale: locale), row: summary.sevenDay, spark: true)
            if showsExtra, let note {
                Text(note)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color(white: 0.55))
                    .lineLimit(2)
            } else if showsExtra, let scoped = summary.highestScoped {
                HStack(spacing: 4) {
                    Text(scoped.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(white: 0.62))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(ClaudeUsageText.percent(scoped.percent))
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color(white: 0.85))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func usageRow(title: String, row: ClaudeUsageRow, spark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.62))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(value(row))
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if row.source == .official, let percent = row.percent {
                ClaudeUsageBar(fraction: min(1, percent / 100), tint: Self.tint(percent))
            } else if spark {
                ClaudeUsageSpark(values: summary.daily)
            } else {
                ClaudeUsageBar(fraction: row.relative ?? 0, tint: Color.white.opacity(0.5))
            }
            Text(caption(row))
                .font(.system(size: 9.5))
                .foregroundStyle(Color(white: 0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func value(_ row: ClaudeUsageRow) -> String {
        if row.source == .official, let percent = row.percent { return ClaudeUsageText.percent(percent) }
        return AgentUsageFormat.tokens(row.totals.tokens)
    }

    private func caption(_ row: ClaudeUsageRow) -> String {
        if row.source == .official, let reset = row.resetsAt {
            return ClaudeUsageText.resets(reset, now: now, locale: locale)
        }
        if showsCost, row.totals.costUSD > 0 { return ClaudeUsageText.cost(row.totals.costUSD) }
        return ClaudeUsageText.turns(row.totals.turns, locale: locale)
    }

    static func tint(_ percent: Double) -> Color {
        if percent > 85 { return .red }
        if percent >= 60 { return .orange }
        return .green
    }
}

struct ClaudeUsageBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(tint)
                    .frame(width: fraction > 0 ? max(4, proxy.size.width * CGFloat(min(1, max(0, fraction)))) : 0)
            }
        }
        .frame(height: 4)
    }
}

struct ClaudeUsageSpark: View {
    let values: [Int]

    var body: some View {
        let peak = max(1, values.max() ?? 1)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.white.opacity(index == values.count - 1 ? 0.6 : 0.3))
                    .frame(maxWidth: .infinity)
                    .frame(height: value == 0 ? 2 : max(3, 12 * CGFloat(value) / CGFloat(peak)))
            }
        }
        .frame(height: 12, alignment: .bottom)
    }
}

struct ClaudeUsageCard: View {
    @ObservedObject var agents = AgentSessionStore.shared
    @ObservedObject var plan = ClaudePlanUsageStore.shared
    let isActive: Bool
    let onOpen: () -> Void

    var body: some View {
        if isActive {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                content(now: context.date)
            }
        } else {
            content(now: Date())
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let summary = agents.usageSummary(now: now) {
            ClaudeUsageCardContent(summary: summary, now: now, note: plan.statusText, onOpen: onOpen)
        }
    }
}
