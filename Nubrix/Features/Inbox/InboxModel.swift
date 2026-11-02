import Foundation

enum InboxSource: String, CaseIterable {
    case claude
    case notchctl
    case github
    case system
}

enum InboxSeverity: Int, Comparable {
    case notice
    case done
    case failed
    case needsYou

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct InboxEntry: Identifiable, Equatable {
    let id = UUID()
    let source: InboxSource
    let severity: InboxSeverity
    let title: String
    let message: String
    let date: Date
    let sessionID: String?
    var isContextWarning = false
    var key: String? = nil
}

struct InboxLedger {
    static let capacity = 50

    private(set) var entries: [InboxEntry] = []

    var unreadCount: Int { entries.count }
    var newest: InboxEntry? { entries.first }
    var topSeverity: InboxSeverity? { entries.map(\.severity).max() }

    func unreadCount(for source: InboxSource) -> Int {
        entries.filter { $0.source == source }.count
    }

    func topSeverity(for source: InboxSource) -> InboxSeverity? {
        entries.filter { $0.source == source }.map(\.severity).max()
    }

    @discardableResult
    mutating func recordSession(id: String, severity: InboxSeverity, title: String, message: String, date: Date = Date()) -> Bool {
        entries.removeAll { $0.source == .claude && $0.sessionID == id && !$0.isContextWarning }
        insert(InboxEntry(source: .claude, severity: severity, title: title, message: message, date: date, sessionID: id))
        return true
    }

    @discardableResult
    mutating func recordContextWarning(id: String, title: String, message: String, date: Date = Date()) -> Bool {
        entries.removeAll { $0.source == .claude && $0.sessionID == id && $0.isContextWarning }
        insert(InboxEntry(source: .claude, severity: .notice, title: title, message: message, date: date, sessionID: id, isContextWarning: true))
        return true
    }

    @discardableResult
    mutating func recordPlanUsage(key: String, severity: InboxSeverity, title: String, message: String, date: Date = Date()) -> Bool {
        let family = key.split(separator: "|").prefix(2).joined(separator: "|") + "|"
        entries.removeAll { $0.source == .claude && $0.key?.hasPrefix(family) == true }
        insert(InboxEntry(source: .claude, severity: severity, title: title, message: message, date: date, sessionID: nil, key: key))
        return true
    }

    @discardableResult
    mutating func clearSession(_ id: String) -> Bool {
        remove { $0.source == .claude && $0.sessionID == id && $0.isContextWarning }
    }

    @discardableResult
    mutating func clearNeedsYou(session id: String) -> Bool {
        remove { $0.source == .claude && $0.sessionID == id && $0.severity == .needsYou }
    }

    @discardableResult
    mutating func recordNotice(title: String, message: String, date: Date = Date()) -> Bool {
        insert(InboxEntry(source: .notchctl, severity: .notice, title: title, message: message, date: date, sessionID: nil))
        return true
    }

    @discardableResult
    mutating func recordSystem(title: String, message: String, date: Date = Date()) -> Bool {
        insert(InboxEntry(source: .system, severity: .notice, title: title, message: message, date: date, sessionID: nil))
        return true
    }

    @discardableResult
    mutating func recordGitHub(key: String, severity: InboxSeverity, title: String, message: String, date: Date = Date()) -> Bool {
        entries.removeAll { $0.source == .github && $0.key == key }
        insert(InboxEntry(source: .github, severity: severity, title: title, message: message, date: date, sessionID: nil, key: key))
        return true
    }

    @discardableResult
    mutating func clearGitHub(keys: [String]) -> Bool {
        let set = Set(keys)
        return remove { $0.source == .github && $0.key.map(set.contains) == true }
    }

    @discardableResult
    mutating func markRead(source: InboxSource) -> Bool {
        remove { $0.source == source }
    }

    @discardableResult
    mutating func markAllRead() -> Bool {
        remove { _ in true }
    }

    private mutating func remove(where predicate: (InboxEntry) -> Bool) -> Bool {
        let before = entries.count
        entries.removeAll(where: predicate)
        return entries.count != before
    }

    private mutating func insert(_ entry: InboxEntry) {
        entries.insert(entry, at: 0)
        while entries.count > Self.capacity {
            if let index = entries.lastIndex(where: { $0.source == .system }) {
                entries.remove(at: index)
            } else {
                entries.removeLast()
            }
        }
    }
}
