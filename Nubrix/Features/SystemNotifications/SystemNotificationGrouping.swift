import AppKit
import Foundation

/// A bundle of notifications shown together in the Notifications tab. Records are newest first.
struct SystemNotificationStack: Identifiable, Equatable {
    let id: String
    let records: [SystemNotificationRecord]
    var isAppGroup = false

    var bundleID: String { records.first?.bundleID ?? "" }
    var appName: String { records.first?.appName ?? "" }
    var recordIDs: Set<UUID> { Set(records.map(\.id)) }

    /// Pure grouping; stacks follow the newest record in each, records inside keep the given order.
    static func stacks(from records: [SystemNotificationRecord], grouping: SystemNotificationGrouping) -> [SystemNotificationStack] {
        switch grouping {
        case .off:
            return records.map { SystemNotificationStack(id: $0.id.uuidString, records: [$0]) }
        case .conversation:
            return group(records, key: { $0.conversationKey }, isApp: false)
        case .app:
            return group(records, key: { "app:" + $0.bundleID }, isApp: true)
        }
    }

    private static func group(_ records: [SystemNotificationRecord], key: (SystemNotificationRecord) -> String,
                              isApp: Bool) -> [SystemNotificationStack] {
        var order: [String] = []
        var groups: [String: [SystemNotificationRecord]] = [:]
        for record in records {
            let k = key(record)
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(record)
        }
        return order.map { SystemNotificationStack(id: $0, records: groups[$0] ?? [], isAppGroup: isApp) }
    }
}

/// Short relative time such as "now", "5m", "2h", "3d".
func systemNotificationAge(from start: Date, to now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(start)))
    if seconds < 60 { return "now" }
    if seconds < 3600 { return "\(seconds / 60)m" }
    if seconds < 86400 { return "\(seconds / 3600)h" }
    return "\(seconds / 86400)d"
}

extension SystemNotificationStore {
    /// The one place that decides whether an arriving notification gets a card.
    static func cardAllowed(showBanner: Bool) -> Bool { showBanner }
}
