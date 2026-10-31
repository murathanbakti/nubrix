import Foundation

struct ClaudeUsageRow: Equatable {
    enum Source: Equatable { case official, estimate }
    enum Origin: Equatable { case none, plan, statusLine }

    var source: Source
    var percent: Double?
    var resetsAt: Date?
    var totals: ClaudeUsageTotals
    var relative: Double?
    var origin: Origin = .none
    var updatedAt: Date? = nil
    var didReset: Bool = false
}

struct ClaudeUsageScoped: Equatable {
    var name: String
    var percent: Double
    var resetsAt: Date? = nil
    var didReset: Bool = false
}

struct ClaudeUsageSummary: Equatable {
    var fiveHour: ClaudeUsageRow
    var sevenDay: ClaudeUsageRow
    var daily: [Int]
    var scoped: [ClaudeUsageScoped] = []
    var planFetchedAt: Date? = nil

    var primaryScoped: ClaudeUsageScoped? {
        scoped.max { $0.percent < $1.percent }
    }

    var hasPlanData: Bool { fiveHour.origin == .plan || sevenDay.origin == .plan }

    var hasOfficial: Bool { fiveHour.source == .official || sevenDay.source == .official }

    func isPlanStale(now: Date) -> Bool {
        guard let planFetchedAt else { return false }
        return now.timeIntervalSince(planFetchedAt) > ClaudePlanPolicy.staleAfter
    }
}

enum ClaudeUsageResolver {
    static let fiveHourFreshness: TimeInterval = 6 * 3600
    static let sevenDayFreshness: TimeInterval = 7 * 24 * 3600

    static func summary(ledger: ClaudeUsageLedger, limits: AgentRateLimits?, limitsUpdatedAt: Date,
                        plan: ClaudePlanSnapshot? = nil, now: Date, calendar: Calendar = .current) -> ClaudeUsageSummary? {
        let five = ledger.rolling(ClaudeUsageLedger.fiveHours, now: now)
        let seven = ledger.rolling(ClaudeUsageLedger.retention, now: now)
        let age = now.timeIntervalSince(limitsUpdatedAt)
        let statusFive = official(percent: limits?.fiveHourPercent, resetsAt: limits?.fiveHourResetsAt,
                                  age: age, freshness: fiveHourFreshness, now: now)
            .map { OfficialValue(percent: $0.percent, resetsAt: $0.resetsAt, updatedAt: limitsUpdatedAt, origin: .statusLine) }
        let statusSeven = official(percent: limits?.sevenDayPercent, resetsAt: limits?.sevenDayResetsAt,
                                   age: age, freshness: sevenDayFreshness, now: now)
            .map { OfficialValue(percent: $0.percent, resetsAt: $0.resetsAt, updatedAt: limitsUpdatedAt, origin: .statusLine) }
        let officialFive = fresher(planValue(plan?.session, fetchedAt: plan?.fetchedAt, now: now), statusFive)
        let officialSeven = fresher(planValue(plan?.weekly, fetchedAt: plan?.fetchedAt, now: now), statusSeven)
        guard seven.turns > 0 || officialFive != nil || officialSeven != nil else { return nil }

        let peak = ledger.peakTokens(window: ClaudeUsageLedger.fiveHours, now: now)
        let relative = peak > 0 ? min(1, Double(five.tokens) / Double(peak)) : nil
        let scoped = (plan?.limits ?? [])
            .filter { $0.kind == ClaudePlanLimit.scopedKind && $0.scopeModel != nil && $0.percent.isFinite }
            .map { limit -> ClaudeUsageScoped in
                let passed = limit.resetsAt.map { $0 <= now } ?? false
                return ClaudeUsageScoped(name: limit.scopeModel ?? "", percent: passed ? 0 : max(0, limit.percent),
                                         resetsAt: limit.resetsAt, didReset: passed)
            }
        let usesPlan = officialFive?.origin == .plan || officialSeven?.origin == .plan
        return ClaudeUsageSummary(
            fiveHour: row(official: officialFive, totals: five, relative: relative),
            sevenDay: row(official: officialSeven, totals: seven, relative: nil),
            daily: ledger.dailyTokens(now: now, calendar: calendar),
            scoped: usesPlan ? scoped : [],
            planFetchedAt: usesPlan ? plan?.fetchedAt : nil)
    }

    struct OfficialValue: Equatable {
        var percent: Double
        var resetsAt: Date?
        var updatedAt: Date
        var origin: ClaudeUsageRow.Origin
        var didReset: Bool = false
    }

    static func planValue(_ limit: ClaudePlanLimit?, fetchedAt: Date?, now: Date) -> OfficialValue? {
        guard let limit, let fetchedAt, limit.percent.isFinite, fetchedAt <= now.addingTimeInterval(60) else { return nil }
        let passed = limit.resetsAt.map { $0 <= now } ?? false
        return OfficialValue(percent: passed ? 0 : max(0, limit.percent), resetsAt: limit.resetsAt,
                             updatedAt: fetchedAt, origin: .plan, didReset: passed)
    }

    static func fresher(_ plan: OfficialValue?, _ status: OfficialValue?) -> OfficialValue? {
        guard let plan else { return status }
        guard let status else { return plan }
        return status.updatedAt > plan.updatedAt ? status : plan
    }

    static func official(percent: Double?, resetsAt: Date?, age: TimeInterval,
                         freshness: TimeInterval, now: Date) -> (percent: Double, resetsAt: Date)? {
        guard let percent, percent.isFinite, let resetsAt, resetsAt > now, age >= 0, age <= freshness else { return nil }
        return (max(0, percent), resetsAt)
    }

    private static func row(official: OfficialValue?, totals: ClaudeUsageTotals, relative: Double?) -> ClaudeUsageRow {
        if let official {
            return ClaudeUsageRow(source: .official, percent: official.percent, resetsAt: official.resetsAt,
                                  totals: totals, relative: nil, origin: official.origin, updatedAt: official.updatedAt,
                                  didReset: official.didReset)
        }
        return ClaudeUsageRow(source: .estimate, percent: nil, resetsAt: nil, totals: totals, relative: relative)
    }
}

enum ClaudeUsageText {
    static func isTurkish(_ locale: Locale) -> Bool {
        locale.language.languageCode?.identifier == "tr"
    }

    static func fiveHour(_ locale: Locale) -> String { isTurkish(locale) ? "5 saat" : "5h" }
    static func sevenDay(_ locale: Locale) -> String { isTurkish(locale) ? "Hafta" : "7d" }
    static func session(_ locale: Locale) -> String { isTurkish(locale) ? "Oturum" : "Session" }
    static func week(_ locale: Locale) -> String { isTurkish(locale) ? "Hafta" : "Week" }

    static func fiveHourTitle(_ row: ClaudeUsageRow, locale: Locale) -> String {
        row.source == .official ? session(locale) : fiveHour(locale)
    }

    static func sevenDayTitle(_ row: ClaudeUsageRow, locale: Locale) -> String {
        row.source == .official ? week(locale) : sevenDay(locale)
    }

    static func clock(_ date: Date, locale: Locale, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: date)
    }

    static func clock24(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    static func percent(_ value: Double, locale: Locale) -> String {
        let number = Int(value.rounded())
        return isTurkish(locale) ? "%\(number)" : "\(number)%"
    }

    static func stamp(_ date: Date, now: Date, locale: Locale, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let sameDay = calendar.isDate(date, inSameDayAs: now)
        formatter.setLocalizedDateFormatFromTemplate(sameDay ? "jmm" : "EEEjmm")
        return formatter.string(from: date)
    }

    static func resetCaption(_ date: Date?, didReset: Bool, now: Date, locale: Locale, calendar: Calendar = .current) -> String? {
        if didReset { return isTurkish(locale) ? "Sıfırlandı · güncelleniyor" : "Reset · updating" }
        guard let date else { return nil }
        let prefix = isTurkish(locale) ? "Sıfırlanma " : "Resets "
        return prefix + stamp(date, now: now, locale: locale, calendar: calendar)
    }

    static func shortReset(_ date: Date?, didReset: Bool, now: Date, locale: Locale, calendar: Calendar = .current) -> String? {
        guard !didReset, let date else { return nil }
        return stamp(date, now: now, locale: locale, calendar: calendar)
    }

    static func cost(_ value: Double) -> String {
        "~" + (value < 10 ? String(format: "$%.2f", value) : String(format: "$%.0f", value))
    }

    static func resets(_ date: Date, now: Date, locale: Locale, calendar: Calendar = .current) -> String {
        (isTurkish(locale) ? "sıfırlanma " : "resets ") + stamp(date, now: now, locale: locale, calendar: calendar)
    }

    static func turns(_ count: Int, locale: Locale) -> String {
        isTurkish(locale) ? "\(count) yanıt" : (count == 1 ? "1 turn" : "\(count) turns")
    }

    static func tooltip(_ summary: ClaudeUsageSummary, now: Date, locale: Locale, calendar: Calendar = .current) -> String {
        let tr = isTurkish(locale)
        let used = tr ? " kullanıldı" : " used"
        func officialLine(_ name: String, percent: Double, reset: Date?, didReset: Bool) -> String {
            var text = name + ": " + Self.percent(percent, locale: locale) + used
            if let caption = resetCaption(reset, didReset: didReset, now: now, locale: locale, calendar: calendar) {
                text += " · " + caption
            }
            return text
        }
        func line(_ name: String, _ row: ClaudeUsageRow) -> String {
            if row.source == .official, let percent = row.percent {
                return officialLine(name, percent: percent, reset: row.resetsAt, didReset: row.didReset)
            }
            var parts = [name + ": "]
            parts.append("\(AgentUsageFormat.tokens(row.totals.tokens)) token")
            if row.totals.costUSD > 0 { parts.append(" · " + cost(row.totals.costUSD)) }
            parts.append(" · " + turns(row.totals.turns, locale: locale))
            return parts.joined()
        }
        var lines = [line(fiveHourTitle(summary.fiveHour, locale: locale), summary.fiveHour),
                     line(sevenDayTitle(summary.sevenDay, locale: locale), summary.sevenDay)]
        for scoped in summary.scoped {
            lines.append(officialLine(scoped.name, percent: scoped.percent, reset: scoped.resetsAt, didReset: scoped.didReset))
        }
        if let fetched = summary.planFetchedAt {
            let when = clock(fetched, locale: locale, calendar: calendar)
            lines.append(tr ? "Resmi kullanım: Claude (/usage) · güncelleme \(when)"
                            : "Official usage from Claude (/usage) · updated \(when)")
            if summary.isPlanStale(now: now) {
                lines.append(tr ? "Veri 30 dakikadan eski; yenilenemedi." : "Data is older than 30 minutes; refresh is not succeeding.")
            }
        }
        let statusLine = summary.fiveHour.origin == .statusLine || summary.sevenDay.origin == .statusLine
        let official = statusLine
        let estimated = summary.fiveHour.source == .estimate || summary.sevenDay.source == .estimate
        if official {
            lines.append(tr ? "Resmi limitler: Claude durum satırından." : "Official limits from the Claude status line.")
        }
        if estimated {
            lines.append(tr
                ? "Tahmin: Claude Code kayıtlarından (giriş, çıkış ve önbellek yazma token'ları; fiyat listesine göre yaklaşık maliyet). Plan limitiniz değildir."
                : "Estimated from your Claude Code transcripts (input, output and cache-write tokens; cost from list prices). Not your plan limit.")
            if summary.fiveHour.source == .estimate {
                lines.append(tr ? "5 saat çubuğu, son 7 gündeki en yoğun 5 saatinize göredir."
                                : "The 5h bar compares with your busiest 5 hours in the last 7 days.")
            }
        }
        return lines.joined(separator: "\n")
    }
}
