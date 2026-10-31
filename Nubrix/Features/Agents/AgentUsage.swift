import Foundation

struct AgentUsageSample: Equatable {
    struct Turn: Equatable {
        let input: Int
        let output: Int
        let cacheRead: Int
        let cacheWrite: Int
        let messageID: String

        var billableTokens: Int { input + output + cacheWrite }
    }

    let contextTokens: Int
    let model: String?
    let turn: Turn?

    init(contextTokens: Int, model: String?, turn: Turn?) {
        self.contextTokens = contextTokens
        self.model = model
        self.turn = turn
    }

    init?(object: [String: Any]?) {
        guard let object, let context = Self.count(object["contextTokens"]) else { return nil }
        contextTokens = context
        let name = Self.identifier(object["model"], limit: 60)
        model = name.isEmpty ? nil : name
        let id = Self.identifier(object["messageId"], limit: 64)
        if let input = Self.count(object["turnInput"]),
           let output = Self.count(object["turnOutput"]),
           let read = Self.count(object["turnCacheRead"]),
           let write = Self.count(object["turnCacheWrite"]),
           !id.isEmpty {
            turn = Turn(input: input, output: output, cacheRead: read, cacheWrite: write, messageID: id)
        } else {
            turn = nil
        }
    }

    static let maxCount = 1_000_000_000_000

    private static func count(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double >= 0, double < Double(maxCount) else { return nil }
        return Int(double)
    }

    private static func identifier(_ value: Any?, limit: Int) -> String {
        guard let text = value as? String else { return "" }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:+[]-")
        let scalars = text.unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(scalars).prefix(limit))
    }
}

enum AgentPricing {
    struct Rate: Equatable {
        let input: Double
        let output: Double
        let cacheRead: Double
        let cacheWrite: Double
    }

    private static func rate(_ input: Double, _ output: Double, cacheRead: Double? = nil) -> Rate {
        Rate(input: input, output: output, cacheRead: cacheRead ?? input * 0.1, cacheWrite: input * 1.25)
    }

    static func rate(for model: String?) -> Rate? {
        guard let id = model?.lowercased(), !id.isEmpty else { return nil }
        if id.contains("fable") || id.contains("mythos") { return rate(10, 50, cacheRead: 0.25) }
        if id.contains("opus-5-5") { return rate(4, 20, cacheRead: 0.20) }
        if id.contains("opus") { return rate(5, 25) }
        if id.contains("sonnet-5") { return rate(2, 10, cacheRead: 0.20) }
        if id.contains("sonnet") { return rate(3, 15) }
        if id.contains("haiku-5") { return rate(0.10, 0.50) }
        if id.contains("haiku") { return rate(1, 5) }
        return nil
    }

    static func cost(of turn: AgentUsageSample.Turn, model: String?) -> Double? {
        guard let rate = rate(for: model) else { return nil }
        let perToken = 1.0 / 1_000_000
        return (Double(turn.input) * rate.input
            + Double(turn.output) * rate.output
            + Double(turn.cacheRead) * rate.cacheRead
            + Double(turn.cacheWrite) * rate.cacheWrite) * perToken
    }

    static func friendlyName(_ model: String?) -> String? {
        guard let id = model?.lowercased() else { return nil }
        guard let regex = try? NSRegularExpression(pattern: "(opus|sonnet|haiku|fable|mythos)-(\\d+)(?:-(\\d{1,2}))?(?![\\d])") else { return nil }
        let range = NSRange(id.startIndex..., in: id)
        guard let match = regex.firstMatch(in: id, range: range),
              let family = Range(match.range(at: 1), in: id),
              let major = Range(match.range(at: 2), in: id) else { return nil }
        var version = String(id[major])
        if let minorRange = Range(match.range(at: 3), in: id) { version += "." + id[minorRange] }
        return id[family].capitalized + " " + version
    }
}

enum AgentContextWindow {
    static let standard = 200_000
    static let extended = 1_000_000

    static func infer(model: String?, contextTokens: Int) -> Int {
        if let model, model.lowercased().contains("[1m]") { return extended }
        return contextTokens > standard ? extended : standard
    }
}

struct AgentDailyUsage: Equatable {
    var dayStart: Date
    var tokens: Int
    var costUSD: Double

    static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    init(dayStart: Date, tokens: Int = 0, costUSD: Double = 0) {
        self.dayStart = dayStart
        self.tokens = tokens
        self.costUSD = costUSD
    }

    init(stored: [String: Double], now: Date = Date(), calendar: Calendar = .current) {
        let today = Self.startOfDay(now, calendar: calendar)
        if let day = stored["day"], day.isFinite, Date(timeIntervalSince1970: day) == today {
            let tokens = stored["tokens"] ?? 0
            let cost = stored["cost"] ?? 0
            self.init(dayStart: today,
                      tokens: tokens.isFinite && tokens >= 0 ? Int(min(tokens, Double(AgentUsageSample.maxCount))) : 0,
                      costUSD: cost.isFinite && cost >= 0 ? cost : 0)
        } else {
            self.init(dayStart: today)
        }
    }

    var stored: [String: Double] {
        ["day": dayStart.timeIntervalSince1970, "tokens": Double(tokens), "cost": costUSD]
    }

    func isCurrent(now: Date, calendar: Calendar = .current) -> Bool {
        dayStart == Self.startOfDay(now, calendar: calendar)
    }

    func current(now: Date, calendar: Calendar = .current) -> AgentDailyUsage {
        isCurrent(now: now, calendar: calendar) ? self : AgentDailyUsage(dayStart: Self.startOfDay(now, calendar: calendar))
    }

    mutating func add(tokens: Int, costUSD: Double, now: Date, calendar: Calendar = .current) {
        if !isCurrent(now: now, calendar: calendar) {
            self = AgentDailyUsage(dayStart: Self.startOfDay(now, calendar: calendar))
        }
        self.tokens = min(AgentUsageSample.maxCount, self.tokens + max(0, tokens))
        self.costUSD += max(0, costUSD)
    }
}

enum AgentUsageFormat {
    static func tokens(_ value: Int) -> String {
        switch value {
        case ..<1000: return "\(value)"
        case ..<9_950: return String(format: "%.1fk", Double(value) / 1000)
        case ..<999_500: return "\(Int((Double(value) / 1000).rounded()))k"
        case ..<9_950_000: return String(format: "%.1fM", Double(value) / 1_000_000)
        default: return "\(Int((Double(value) / 1_000_000).rounded()))M"
        }
    }

    static func window(_ size: Int) -> String {
        size >= 1_000_000 ? "\(size / 1_000_000)M" : "\(size / 1000)k"
    }
}
