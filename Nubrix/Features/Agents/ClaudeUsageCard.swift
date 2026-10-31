import SwiftUI

struct ClaudeUsageCardContent: View {
    let summary: ClaudeUsageSummary
    let now: Date
    var width: CGFloat = 140
    var showsCost = true
    var note: String?
    let onOpen: () -> Void
    @Environment(\.locale) private var locale

    static let timestampAfter: TimeInterval = 10 * 60
    private static let sectionSpacing: CGFloat = 5
    private static let weeklyMatchTolerance: TimeInterval = 120

    var body: some View {
        Button(action: onOpen) {
            variants
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
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

    @ViewBuilder
    private var variants: some View {
        if summary.hasOfficial {
            ViewThatFits(in: .vertical) {
                stack { header; fiveHourRow; sevenDayRow; scopedRow(compact: false) }
                stack { header; fiveHourRow; sevenDayRow; scopedRow(compact: true) }
                stack { fiveHourRow; sevenDayRow; scopedRow(compact: false) }
                stack { header; fiveHourRow; sevenDayRow }
                stack { fiveHourRow; sevenDayRow }
            }
        } else {
            ViewThatFits(in: .vertical) {
                stack { header; estimateRow(summary.fiveHour, title: fiveHourTitle, visual: .bar)
                    estimateRow(summary.sevenDay, title: sevenDayTitle, visual: .sparkOrNote) }
                stack { header; estimateRow(summary.fiveHour, title: fiveHourTitle, visual: .bar)
                    estimateRow(summary.sevenDay, title: sevenDayTitle, visual: .none) }
                stack { estimateRow(summary.fiveHour, title: fiveHourTitle, visual: .bar)
                    estimateRow(summary.sevenDay, title: sevenDayTitle, visual: .none) }
            }
        }
    }

    private func stack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Self.sectionSpacing) {
            content()
        }
    }

    private var fiveHourTitle: String { ClaudeUsageText.fiveHourTitle(summary.fiveHour, locale: locale) }
    private var sevenDayTitle: String { ClaudeUsageText.sevenDayTitle(summary.sevenDay, locale: locale) }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AgentSessionState.working.tint)
            Text("Claude")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let fetched = summary.planFetchedAt, now.timeIntervalSince(fetched) > Self.timestampAfter {
                let stale = summary.isPlanStale(now: now)
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 8.5, weight: .medium))
                    Text(ClaudeUsageText.clock24(fetched))
                        .font(.system(size: 9.5).monospacedDigit())
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(stale ? Color.orange.opacity(0.8) : Color(white: 0.55))
            }
        }
        .frame(height: 14)
    }

    @ViewBuilder
    private var fiveHourRow: some View {
        if summary.fiveHour.source == .official {
            officialRow(title: fiveHourTitle, row: summary.fiveHour)
        } else {
            estimateRow(summary.fiveHour, title: fiveHourTitle, visual: .bar)
        }
    }

    @ViewBuilder
    private var sevenDayRow: some View {
        if summary.sevenDay.source == .official {
            officialRow(title: sevenDayTitle, row: summary.sevenDay)
        } else {
            estimateRow(summary.sevenDay, title: sevenDayTitle, visual: .bar)
        }
    }

    @ViewBuilder
    private func scopedRow(compact: Bool) -> some View {
        if let scoped = summary.primaryScoped {
            if compact {
                HStack(spacing: 5) {
                    Text(scoped.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(white: 0.62))
                        .lineLimit(1)
                        .fixedSize()
                    ClaudeUsageBar(fraction: min(1, scoped.percent / 100), tint: Self.tint(scoped.percent))
                    Text(ClaudeUsageText.percent(scoped.percent, locale: locale))
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(height: 13)
            } else {
                meterRow(title: scoped.name, percent: scoped.percent, caption: scopedCaption(scoped))
            }
        }
    }

    private func scopedCaption(_ scoped: ClaudeUsageScoped) -> String? {
        let weekly = summary.sevenDay
        if scoped.didReset == weekly.didReset {
            if scoped.didReset { return nil }
            if let a = scoped.resetsAt, let b = weekly.resetsAt, abs(a.timeIntervalSince(b)) <= Self.weeklyMatchTolerance { return nil }
        }
        return ClaudeUsageText.resetCaption(scoped.resetsAt, didReset: scoped.didReset, now: now, locale: locale)
    }

    private func officialRow(title: String, row: ClaudeUsageRow) -> some View {
        meterRow(title: title, percent: row.percent ?? 0,
                 caption: ClaudeUsageText.resetCaption(row.resetsAt, didReset: row.didReset, now: now, locale: locale))
    }

    private func meterRow(title: String, percent: Double, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.62))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(ClaudeUsageText.percent(percent, locale: locale))
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            ClaudeUsageBar(fraction: min(1, percent / 100), tint: Self.tint(percent))
            if let caption {
                Text(caption)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color(white: 0.55))
                    .lineLimit(1)
            }
        }
    }

    private enum EstimateVisual { case bar, sparkOrNote, none }

    private func estimateRow(_ row: ClaudeUsageRow, title: String, visual: EstimateVisual) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.62))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(AgentUsageFormat.tokens(row.totals.tokens))
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            switch visual {
            case .bar:
                if row.source == .official, let percent = row.percent {
                    ClaudeUsageBar(fraction: min(1, percent / 100), tint: Self.tint(percent))
                } else {
                    ClaudeUsageBar(fraction: row.relative ?? 0, tint: Color.white.opacity(0.5))
                }
            case .sparkOrNote:
                if let note {
                    Text(note)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color(white: 0.55))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ClaudeUsageSpark(values: summary.daily)
                }
            case .none:
                EmptyView()
            }
            Text(estimateCaption(row))
                .font(.system(size: 9.5))
                .foregroundStyle(Color(white: 0.55))
                .lineLimit(1)
        }
    }

    private func estimateCaption(_ row: ClaudeUsageRow) -> String {
        if showsCost, row.totals.costUSD > 0 { return ClaudeUsageText.cost(row.totals.costUSD) }
        return ClaudeUsageText.turns(row.totals.turns, locale: locale)
    }

    static func tint(_ percent: Double) -> Color {
        AgentMeter.color(for: percent)
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
