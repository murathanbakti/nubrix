import Foundation

enum InboxSource: String, CaseIterable {
    case claude
    case notchctl
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

    mutating func recordSession(id: String, severity: InboxSeverity, title: String, message: String, date: Date = Date()) {
        entries.removeAll { $0.source == .claude && $0.sessionID == id }
        insert(InboxEntry(source: .claude, severity: severity, title: title, message: message, date: date, sessionID: id))
    }

    mutating func clearNeedsYou(session id: String) {
        entries.removeAll { $0.source == .claude && $0.sessionID == id && $0.severity == .needsYou }
    }

    mutating func recordNotice(title: String, message: String, date: Date = Date()) {
        insert(InboxEntry(source: .notchctl, severity: .notice, title: title, message: message, date: date, sessionID: nil))
    }

    mutating func markRead(source: InboxSource) {
        entries.removeAll { $0.source == source }
    }

    mutating func markAllRead() {
        entries.removeAll()
    }

    private mutating func insert(_ entry: InboxEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
    }
}
