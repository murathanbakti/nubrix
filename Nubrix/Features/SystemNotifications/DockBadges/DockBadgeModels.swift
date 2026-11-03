import Foundation

struct DockBadge: Equatable, Identifiable, Sendable {
    let bundleID: String
    let label: String
    let count: Int?

    var id: String { bundleID }
    var weight: Int { count ?? 1 }
}

enum DockBadgeLabel {
    static let maxLength = 8

    static func parse(_ raw: String?) -> (label: String, count: Int?)? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var count: Int?
        if isDigits(trimmed) {
            if let number = Int(trimmed) {
                if number == 0 { return nil }
                count = number
            } else if trimmed.allSatisfy({ $0 == "0" }) {
                return nil
            }
        } else if trimmed.hasSuffix("+") {
            let digits = String(trimmed.dropLast())
            if isDigits(digits) {
                count = Int(digits)
                if count == 0 { return nil }
            }
        }
        return (String(trimmed.prefix(maxLength)), count)
    }

    private static func isDigits(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { $0.value >= 48 && $0.value <= 57 }
    }
}

struct DockBadgeSummary: Equatable {
    let badges: [DockBadge]

    static let empty = DockBadgeSummary(badges: [], order: [])

    init(badges: [DockBadge], order: [String]) {
        var positions: [String: Int] = [:]
        for (index, id) in order.enumerated() where positions[id] == nil { positions[id] = index }
        self.badges = badges.sorted { lhs, rhs in
            if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
            let l = positions[lhs.bundleID] ?? Int.max
            let r = positions[rhs.bundleID] ?? Int.max
            if l != r { return l < r }
            return lhs.bundleID < rhs.bundleID
        }
    }

    var total: Int { badges.reduce(0) { $0 + $1.weight } }
    var top: DockBadge? { badges.first }
    var isEmpty: Bool { badges.isEmpty }

    var totalText: String {
        let total = total
        if total <= 0 { return "" }
        return total > 99 ? "99+" : String(total)
    }

    func badge(for bundleID: String) -> DockBadge? {
        badges.first { $0.bundleID == bundleID }
    }
}

enum DockBadgeAppList {
    static let defaults: [String] = [
        "net.whatsapp.WhatsApp", "desktop.WhatsApp", "com.apple.MobileSMS", "com.apple.mail",
        "com.tinyspeck.slackmacgap", "com.microsoft.teams2", "ru.keepcoder.Telegram", "com.hnc.Discord"
    ]

    static func rows(known: [String], allowed: [String], running: [String],
                     defaults: [String] = DockBadgeAppList.defaults,
                     ownBundleID: String?, isInstalled: (String) -> Bool) -> [String] {
        var result = Set<String>()
        result.formUnion(known)
        result.formUnion(allowed)
        result.formUnion(running)
        for id in defaults where isInstalled(id) { result.insert(id) }
        result.remove("")
        if let ownBundleID { result.remove(ownBundleID) }
        return result.sorted()
    }
}

enum DockBadgeStatus: Equatable {
    case off, ready, unavailable
}
