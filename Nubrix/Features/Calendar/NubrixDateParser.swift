import Foundation

enum NubrixDateParseFailure: Equatable {
    case empty
    case invalidDate
    case unrecognized
}

enum NubrixDateParseResult: Equatable {
    case success(Date)
    case failure(NubrixDateParseFailure)
}

struct NubrixDateParser {
    var calendar: Calendar
    var now: Date

    init(calendar: Calendar = .autoupdatingCurrent, now: Date = Date()) {
        self.calendar = calendar
        self.now = now
    }

    static func fold(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "ı", with: "i")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let keywordOffsets: [String: Int] = [
        "bugun": 0, "today": 0, "simdi": 0, "now": 0,
        "yarin": 1, "tomorrow": 1,
        "obur gun": 2, "ertesi gun": 2,
        "dun": -1, "yesterday": -1
    ]

    private static let weekdayNames: [String: Int] = [
        "pazar": 1, "pazartesi": 2, "sali": 3, "carsamba": 4, "persembe": 5, "cuma": 6, "cumartesi": 7,
        "paz": 1, "pzt": 2, "sal": 3, "car": 4, "per": 5, "cum": 6, "cmt": 7,
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
        "sun": 1, "mon": 2, "tue": 3, "tues": 3, "wed": 4, "thu": 5, "thur": 5, "thurs": 5, "fri": 6, "sat": 7
    ]

    private static let monthNames: [String: Int] = {
        var map: [String: Int] = ["sept": 9]
        for identifier in ["tr_TR", "en_US"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: identifier)
            for symbols in [formatter.monthSymbols, formatter.shortMonthSymbols, formatter.standaloneMonthSymbols] {
                for (index, name) in (symbols ?? []).enumerated() {
                    map[fold(name)] = index + 1
                }
            }
        }
        return map
    }()

    private static let relativePrefixes = ["next ", "gelecek ", "onumuzdeki ", "haftaya "]

    private static let fallbackFormats = [
        "d MMMM yyyy", "d MMM yyyy", "MMMM d, yyyy", "MMM d, yyyy", "MMMM d yyyy",
        "EEEE, d MMMM yyyy", "d MMMM yyyy EEEE", "d MMMM yyyy, EEEE",
        "yyyy-MM-dd", "dd.MM.yyyy", "dd/MM/yyyy", "d.M.yyyy"
    ]

    func parse(_ raw: String) -> NubrixDateParseResult {
        var text = Self.fold(raw)
        text = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !text.isEmpty else { return .failure(.empty) }
        let today = calendar.startOfDay(for: now)

        if let offset = Self.keywordOffsets[text] {
            return add(days: offset, to: today)
        }
        for prefix in Self.relativePrefixes where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
            break
        }
        if let weekday = Self.weekdayNames[text] {
            return nextWeekday(weekday, after: today)
        }
        if let result = parseRelative(text, today: today) { return result }
        if let result = parseNumeric(text, today: today) { return result }
        if let result = parseTokens(text, today: today) { return result }
        if let date = parseWithFormatters(raw) { return finish(date) }
        if let date = parseWithDetector(raw) { return finish(date) }
        return .failure(.unrecognized)
    }

    private func finish(_ date: Date) -> NubrixDateParseResult {
        let year = calendar.component(.year, from: date)
        guard (1900...2200).contains(year) else { return .failure(.invalidDate) }
        return .success(calendar.startOfDay(for: date))
    }

    private func add(days: Int, to date: Date) -> NubrixDateParseResult {
        guard let result = calendar.date(byAdding: .day, value: days, to: date) else { return .failure(.invalidDate) }
        return finish(result)
    }

    private func nextWeekday(_ weekday: Int, after today: Date) -> NubrixDateParseResult {
        let current = calendar.component(.weekday, from: today)
        var delta = (weekday - current + 7) % 7
        if delta == 0 { delta = 7 }
        return add(days: delta, to: today)
    }

    private func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            let r = match.range(at: index)
            guard r.location != NSNotFound, let swiftRange = Range(r, in: text) else { return "" }
            return String(text[swiftRange])
        }
    }

    private func parseRelative(_ text: String, today: Date) -> NubrixDateParseResult? {
        guard let parts = captures(#"^([+-])\s*(\d{1,5})\s*([a-z]*)$"#, in: text),
              let amount = Int(parts[1]) else { return nil }
        let multiplier: Int
        switch parts[2] {
        case "", "d", "g", "gun", "day", "days": multiplier = 1
        case "w", "hafta", "week", "weeks": multiplier = 7
        default: return nil
        }
        let sign = parts[0] == "-" ? -1 : 1
        return add(days: sign * amount * multiplier, to: today)
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date? {
        guard (1900...2200).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        guard let date = calendar.date(from: components) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }

    private func nextOccurrence(month: Int, day: Int, today: Date) -> Date? {
        let startYear = calendar.component(.year, from: today)
        for year in startYear...(startYear + 8) {
            if let date = makeDate(year, month, day), date >= today { return date }
        }
        return nil
    }

    private func resolve(day: Int, month: Int, year: Int?, today: Date) -> Date? {
        if let year { return makeDate(year, month, day) }
        return nextOccurrence(month: month, day: day, today: today)
    }

    private func expandYear(_ text: String) -> Int? {
        guard let value = Int(text) else { return nil }
        return text.count == 2 ? 2000 + value : value
    }

    private func parseNumeric(_ text: String, today: Date) -> NubrixDateParseResult? {
        if let parts = captures(#"^(\d{4})[./\-](\d{1,2})[./\-](\d{1,2})$"#, in: text),
           let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) {
            guard let date = makeDate(year, month, day) else { return .failure(.invalidDate) }
            return finish(date)
        }
        if let parts = captures(#"^(\d{1,2})[./\-](\d{1,2})(?:[./\-](\d{4}|\d{2}))?\.?$"#, in: text),
           let first = Int(parts[0]), let second = Int(parts[1]) {
            let year = parts[2].isEmpty ? nil : expandYear(parts[2])
            var candidates = [(day: first, month: second)]
            if first <= 12 && second > 12 { candidates.append((day: second, month: first)) }
            for candidate in candidates {
                if let date = resolve(day: candidate.day, month: candidate.month, year: year, today: today) {
                    return finish(date)
                }
            }
            return .failure(.invalidDate)
        }
        if let parts = captures(#"^(\d{1,2})\.?$"#, in: text), let day = Int(parts[0]) {
            guard (1...31).contains(day) else { return .failure(.invalidDate) }
            let base = calendar.dateComponents([.year, .month], from: today)
            for offset in 0..<14 {
                var components = DateComponents()
                components.year = base.year
                components.month = (base.month ?? 1) + offset
                components.day = 1
                guard let monthStart = calendar.date(from: components) else { continue }
                let parts = calendar.dateComponents([.year, .month], from: monthStart)
                if let year = parts.year, let month = parts.month,
                   let date = makeDate(year, month, day), date >= today {
                    return finish(date)
                }
            }
            return .failure(.invalidDate)
        }
        return nil
    }

    private func parseTokens(_ text: String, today: Date) -> NubrixDateParseResult? {
        let tokens = text.components(separatedBy: CharacterSet(charactersIn: " ,./-'")).filter { !$0.isEmpty }
        var month: Int?
        var year: Int?
        var numbers: [Int] = []
        for token in tokens {
            if let value = Self.monthNames[token], month == nil {
                month = value
            } else if Self.weekdayNames[token] != nil {
                continue
            } else if let parts = captures(#"^(\d{4})$"#, in: token), year == nil {
                year = Int(parts[0])
            } else if let parts = captures(#"^(\d{1,2})(?:st|nd|rd|th)?$"#, in: token), let value = Int(parts[0]) {
                numbers.append(value)
            } else {
                return nil
            }
        }
        guard let month, numbers.count <= 2 else { return nil }
        if numbers.count == 2, year == nil { year = 2000 + numbers[1] }
        else if numbers.count == 2 { return nil }

        if let day = numbers.first {
            guard let date = resolve(day: day, month: month, year: year, today: today) else {
                return .failure(.invalidDate)
            }
            return finish(date)
        }
        if let year {
            guard let date = makeDate(year, month, 1) else { return .failure(.invalidDate) }
            return finish(date)
        }
        let currentMonth = calendar.component(.month, from: today)
        if currentMonth == month { return finish(today) }
        guard let date = nextOccurrence(month: month, day: 1, today: today) else { return .failure(.invalidDate) }
        return finish(date)
    }

    private func parseWithFormatters(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for identifier in ["tr_TR", "en_US"] {
            for format in Self.fallbackFormats {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: identifier)
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.isLenient = false
                formatter.dateFormat = format
                if let date = formatter.date(from: trimmed) { return date }
            }
        }
        return nil
    }

    private func parseWithDetector(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let date = match.date else { return nil }
        let coverage = Double(match.range.length) / Double(max(trimmed.utf16.count, 1))
        return coverage >= 0.6 ? date : nil
    }
}
