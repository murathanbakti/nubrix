import Foundation

struct ClaudePlanLimit: Codable, Equatable, Sendable {
    static let sessionKind = "session"
    static let weeklyKind = "weekly_all"
    static let scopedKind = "weekly_scoped"

    var kind: String
    var group: String
    var percent: Double
    var resetsAt: Date?
    var isActive: Bool
    var severity: String
    var scopeModel: String?

    private enum Keys: String, CodingKey {
        case kind, group, percent, resetsAt, isActive, severity, scopeModel
    }

    init(kind: String, group: String, percent: Double, resetsAt: Date?, isActive: Bool = false,
         severity: String = "normal", scopeModel: String? = nil) {
        self.kind = kind
        self.group = group
        self.percent = percent
        self.resetsAt = resetsAt
        self.isActive = isActive
        self.severity = severity
        self.scopeModel = scopeModel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        kind = try container.decode(String.self, forKey: .kind)
        group = try container.decodeIfPresent(String.self, forKey: .group) ?? ""
        let raw = try container.decode(Double.self, forKey: .percent)
        guard raw.isFinite else { throw DecodingError.dataCorruptedError(forKey: .percent, in: container, debugDescription: "percent") }
        percent = min(100, max(0, raw))
        resetsAt = try container.decodeIfPresent(Double.self, forKey: .resetsAt)
            .flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        severity = try container.decodeIfPresent(String.self, forKey: .severity) ?? ""
        scopeModel = try container.decodeIfPresent(String.self, forKey: .scopeModel)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(group, forKey: .group)
        try container.encode(percent, forKey: .percent)
        try container.encodeIfPresent(resetsAt?.timeIntervalSince1970, forKey: .resetsAt)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(severity, forKey: .severity)
        try container.encodeIfPresent(scopeModel, forKey: .scopeModel)
    }
}

enum ClaudePlanFailure: String, Codable, Sendable {
    case notInstalled
    case notSubscriber
    case timeout
    case failed
    case unsupported

    var isHard: Bool { self == .notInstalled || self == .unsupported }
}

struct ClaudePlanSnapshot: Codable, Equatable, Sendable {
    static let maxLimits = 16

    var limits: [ClaudePlanLimit]
    var fetchedAt: Date

    private enum Keys: String, CodingKey { case limits, fetchedAt }

    init(limits: [ClaudePlanLimit], fetchedAt: Date) {
        self.limits = limits
        self.fetchedAt = fetchedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        limits = Array(try container.decode([ClaudePlanLimit].self, forKey: .limits).prefix(Self.maxLimits))
        let seconds = try container.decode(Double.self, forKey: .fetchedAt)
        guard seconds.isFinite else { throw DecodingError.dataCorruptedError(forKey: .fetchedAt, in: container, debugDescription: "fetchedAt") }
        fetchedAt = Date(timeIntervalSince1970: seconds)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(limits, forKey: .limits)
        try container.encode(fetchedAt.timeIntervalSince1970, forKey: .fetchedAt)
    }

    var session: ClaudePlanLimit? { limits.first { $0.kind == ClaudePlanLimit.sessionKind } }
    var weekly: ClaudePlanLimit? { limits.first { $0.kind == ClaudePlanLimit.weeklyKind } }

    var busiestScoped: ClaudePlanLimit? {
        limits.filter { $0.kind == ClaudePlanLimit.scopedKind && $0.percent > 0 && $0.scopeModel != nil }
            .max { $0.percent < $1.percent }
    }

    func isStale(now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) > ClaudePlanPolicy.staleAfter
    }
}

enum ClaudePlanFetchResult: Equatable, Sendable {
    case success(ClaudePlanSnapshot)
    case failure(ClaudePlanFailure)

    private struct Envelope: Decodable {
        var limits: [ClaudePlanLimit]?
        var fetchedAt: Double?
        var error: ClaudePlanFailure?
    }

    static let maxEnvelopeBytes = 64 * 1024

    static func decode(_ data: Data) -> ClaudePlanFetchResult {
        guard data.count <= maxEnvelopeBytes,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return .failure(.failed) }
        if let error = envelope.error { return .failure(error) }
        guard let limits = envelope.limits, !limits.isEmpty,
              let stamp = envelope.fetchedAt, stamp.isFinite else { return .failure(.failed) }
        return .success(ClaudePlanSnapshot(limits: Array(limits.prefix(ClaudePlanSnapshot.maxLimits)),
                                           fetchedAt: Date(timeIntervalSince1970: stamp)))
    }
}

enum ClaudePlanPolicy {
    static let activeInterval: TimeInterval = 5 * 60
    static let idleInterval: TimeInterval = 30 * 60
    static let maxBackoff: TimeInterval = 30 * 60
    static let activityWindow: TimeInterval = 60 * 60
    static let staleAfter: TimeInterval = 30 * 60
    static let openRefreshAge: TimeInterval = 2 * 60
    static let stopRefreshGap: TimeInterval = 2 * 60
    static let requestTimeout: TimeInterval = 45
    static let dormantAfter: TimeInterval = 6 * 3600
    static let dormantInterval: TimeInterval = 2 * 3600
    static let hardRetryInterval: TimeInterval = 6 * 3600
    static let maxDelay: TimeInterval = 4 * 3600
    static let batteryFactor = 2.0
    static let lowPowerFactor = 4.0

    static func baseInterval(lastActivity: Date?, now: Date) -> TimeInterval {
        guard let lastActivity else { return idleInterval }
        let age = now.timeIntervalSince(lastActivity)
        if age <= activityWindow { return activeInterval }
        if age <= dormantAfter { return idleInterval }
        return dormantInterval
    }

    static func delay(base: TimeInterval, failures: Int) -> TimeInterval {
        guard failures > 0 else { return base }
        let factor = pow(2.0, Double(min(failures, 8)))
        return min(max(maxBackoff, base), max(base, base * factor))
    }

    static func effectiveBase(lastActivity: Date?, now: Date, onBattery: Bool, lowPower: Bool) -> TimeInterval {
        let base = baseInterval(lastActivity: lastActivity, now: now)
        if lowPower { return base * lowPowerFactor }
        return onBattery ? base * batteryFactor : base
    }

    static func timerDelay(lastActivity: Date?, now: Date, failures: Int, onBattery: Bool, lowPower: Bool) -> TimeInterval {
        let base = effectiveBase(lastActivity: lastActivity, now: now, onBattery: onBattery, lowPower: lowPower)
        return min(maxDelay, delay(base: base, failures: failures))
    }

    static func resumeWait(lastAttempt: Date?, delay: TimeInterval, now: Date, minimum: TimeInterval) -> TimeInterval {
        guard let lastAttempt else { return minimum }
        return max(minimum, lastAttempt.addingTimeInterval(delay).timeIntervalSince(now))
    }

    static func shouldRefreshOnOpen(lastAttempt: Date?, lastSuccess: Date?, failures: Int,
                                    base: TimeInterval, hardFailure: Bool = false, now: Date) -> Bool {
        if let lastAttempt {
            let gap = now.timeIntervalSince(lastAttempt)
            if gap < openRefreshAge { return false }
            if hardFailure { return gap >= hardRetryInterval }
            if failures > 0 { return gap >= delay(base: base, failures: failures) }
        }
        guard let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) >= openRefreshAge
    }

    static func allowsStopRefresh(lastStopRefresh: Date?, now: Date) -> Bool {
        guard let lastStopRefresh else { return true }
        return now.timeIntervalSince(lastStopRefresh) >= stopRefreshGap
    }
}

struct ClaudePlanAlert: Equatable {
    let key: String
    let kind: String
    let threshold: Int
    let percent: Double
    let resetsAt: Date

    var isSession: Bool { kind == ClaudePlanLimit.sessionKind }
}

struct ClaudePlanAlertTracker: Equatable {
    static let thresholds = [80, 95]
    static let retention: TimeInterval = 2 * 24 * 3600

    private(set) var fired: Set<String>

    init(fired: Set<String> = []) {
        self.fired = fired
    }

    mutating func newAlerts(for snapshot: ClaudePlanSnapshot, now: Date) -> [ClaudePlanAlert] {
        prune(now: now)
        var alerts: [ClaudePlanAlert] = []
        for limit in [snapshot.session, snapshot.weekly].compactMap({ $0 }) {
            guard let reset = limit.resetsAt, reset > now else { continue }
            let bucket = Int((reset.timeIntervalSince1970 / 60).rounded())
            let crossed = Self.thresholds.filter { limit.percent >= Double($0) }
            guard let top = crossed.last else { continue }
            let topKey = Self.key(limit.kind, bucket, top)
            guard !fired.contains(topKey) else { continue }
            for threshold in crossed { fired.insert(Self.key(limit.kind, bucket, threshold)) }
            alerts.append(ClaudePlanAlert(key: topKey, kind: limit.kind, threshold: top, percent: limit.percent, resetsAt: reset))
        }
        return alerts
    }

    mutating func prune(now: Date) {
        let floor = Int(((now.timeIntervalSince1970 - Self.retention) / 60).rounded())
        fired = fired.filter { key in
            let parts = key.split(separator: "|")
            guard parts.count == 3, let bucket = Int(parts[1]) else { return false }
            return bucket >= floor
        }
    }

    private static func key(_ kind: String, _ bucket: Int, _ threshold: Int) -> String {
        "\(kind)|\(bucket)|\(threshold)"
    }
}
