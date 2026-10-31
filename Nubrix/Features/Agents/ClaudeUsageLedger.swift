import CryptoKit
import Foundation

struct ClaudeUsageRecord: Codable, Equatable, Sendable {
    var date: Date
    var session: String?
    var tokens: Int
    var costUSD: Double
    var model: String?

    private enum Keys: String, CodingKey {
        case date = "d", session = "s", tokens = "t", cost = "c", model = "m"
    }

    init(date: Date, session: String?, tokens: Int, costUSD: Double, model: String?) {
        self.date = date
        self.session = session
        self.tokens = tokens
        self.costUSD = costUSD
        self.model = model
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        date = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .date))
        session = try container.decodeIfPresent(String.self, forKey: .session)
        tokens = try container.decode(Int.self, forKey: .tokens)
        costUSD = try container.decodeIfPresent(Double.self, forKey: .cost) ?? 0
        model = try container.decodeIfPresent(String.self, forKey: .model)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(Double(Int(date.timeIntervalSince1970)), forKey: .date)
        try container.encodeIfPresent(session, forKey: .session)
        try container.encode(tokens, forKey: .tokens)
        if costUSD > 0 { try container.encode((costUSD * 1_000_000).rounded() / 1_000_000, forKey: .cost) }
        try container.encodeIfPresent(model, forKey: .model)
    }

    var isValid: Bool {
        date.timeIntervalSince1970.isFinite && tokens >= 0 && tokens <= AgentUsageSample.maxCount
            && costUSD.isFinite && costUSD >= 0
    }

    static func sessionHash(_ id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}

struct ClaudeUsageTotals: Equatable, Sendable {
    var tokens = 0
    var costUSD = 0.0
    var turns = 0

    static let zero = ClaudeUsageTotals()
}

struct ClaudeUsageLedger: Equatable, Sendable {
    static let retention: TimeInterval = 7 * 24 * 3600
    static let maxRecords = 20_000
    static let fiveHours: TimeInterval = 5 * 3600

    private(set) var records: [ClaudeUsageRecord] = []

    init() {}

    init(records: [ClaudeUsageRecord], now: Date) {
        self.records = records.filter(\.isValid).map { record in
            var copy = record
            if copy.date > now { copy.date = now }
            return copy
        }.sorted { $0.date < $1.date }
        prune(now: now)
    }

    mutating func append(_ record: ClaudeUsageRecord, now: Date) {
        guard record.isValid else { return }
        var record = record
        if record.date > now { record.date = now }
        if let last = records.last, record.date < last.date {
            let index = records.firstIndex { $0.date > record.date } ?? records.endIndex
            records.insert(record, at: index)
        } else {
            records.append(record)
        }
        prune(now: now)
    }

    mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        if let first = records.first, first.date <= cutoff {
            let keep = records.firstIndex { $0.date > cutoff } ?? records.endIndex
            records.removeFirst(keep)
        }
        if records.count > Self.maxRecords { records.removeFirst(records.count - Self.maxRecords) }
    }

    static func migratedRecord(daily: AgentDailyUsage) -> ClaudeUsageRecord? {
        guard daily.tokens > 0 || daily.costUSD > 0 else { return nil }
        return ClaudeUsageRecord(date: daily.dayStart.addingTimeInterval(1), session: nil, tokens: daily.tokens,
                                 costUSD: daily.costUSD, model: nil)
    }

    func totals(after start: Date, through end: Date) -> ClaudeUsageTotals {
        var result = ClaudeUsageTotals()
        for record in records.reversed() {
            if record.date <= start { break }
            if record.date > end { continue }
            result.tokens = min(AgentUsageSample.maxCount, result.tokens + record.tokens)
            result.costUSD += record.costUSD
            result.turns += 1
        }
        return result
    }

    func rolling(_ length: TimeInterval, now: Date) -> ClaudeUsageTotals {
        totals(after: now.addingTimeInterval(-length), through: now)
    }

    func hasActivity(now: Date) -> Bool {
        rolling(Self.retention, now: now).turns > 0
    }

    func today(now: Date, calendar: Calendar = .current) -> AgentDailyUsage {
        let start = calendar.startOfDay(for: now)
        let sum = totals(after: start.addingTimeInterval(-0.001), through: now)
        return AgentDailyUsage(dayStart: start, tokens: sum.tokens, costUSD: sum.costUSD)
    }

    func peakTokens(window length: TimeInterval, now: Date) -> Int {
        let cutoff = now.addingTimeInterval(-Self.retention)
        let items = records.filter { $0.date > cutoff && $0.date <= now }
        var best = 0
        var sum = 0
        var tail = 0
        for index in items.indices {
            sum += items[index].tokens
            while items[index].date.timeIntervalSince(items[tail].date) >= length {
                sum -= items[tail].tokens
                tail += 1
            }
            best = max(best, sum)
        }
        return best
    }

    func dailyTokens(now: Date, calendar: Calendar = .current, days: Int = 7) -> [Int] {
        let today = calendar.startOfDay(for: now)
        var starts: [Date] = []
        for back in stride(from: days - 1, through: 0, by: -1) {
            starts.append(calendar.date(byAdding: .day, value: -back, to: today) ?? today)
        }
        var result = Array(repeating: 0, count: days)
        for record in records where record.date <= now {
            guard let index = starts.lastIndex(where: { $0 <= record.date }) else { continue }
            result[index] += record.tokens
        }
        return result
    }
}

enum ClaudeUsageLedgerFile {
    static let formatVersion = 1

    private struct Envelope: Codable {
        var version: Int
        var records: [ClaudeUsageRecord]
    }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Nubrix", isDirectory: true).appendingPathComponent("claude-usage.json")
    }

    static func load(from url: URL, now: Date) -> ClaudeUsageLedger {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count < 16_000_000,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data), envelope.version == formatVersion
        else { return ClaudeUsageLedger() }
        return ClaudeUsageLedger(records: envelope.records, now: now)
    }

    @discardableResult
    static func write(_ ledger: ClaudeUsageLedger, to url: URL) -> Bool {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(Envelope(version: formatVersion, records: ledger.records))
            let temp = directory.appendingPathComponent(".claude-usage-\(UUID().uuidString).tmp")
            guard fileManager.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return false }
            if rename(temp.path, url.path) != 0 {
                try? fileManager.removeItem(at: temp)
                return false
            }
            return true
        } catch {
            return false
        }
    }
}
