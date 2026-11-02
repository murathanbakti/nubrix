import Foundation

enum SystemNotificationHelperStatus: String, Decodable, Sendable {
    case ok
    case noAccess
    case notFound
    case unsupported
    case failed
}

struct SystemNotificationItem: Decodable, Equatable, Sendable {
    var id: Int64
    var bundleID: String
    var title: String
    var subtitle: String
    var body: String
    var date: Double
}

struct SystemNotificationFetch: Equatable, Sendable {
    var status: SystemNotificationHelperStatus
    var cursor: Int64
    var items: [SystemNotificationItem]

    static let failed = SystemNotificationFetch(status: .failed, cursor: -1, items: [])
    static let maxBytes = 512 * 1024

    private struct Envelope: Decodable {
        var status: String
        var cursor: Int64?
        var items: [SystemNotificationItem]?
    }

    static func decode(_ data: Data) -> SystemNotificationFetch {
        guard data.count <= maxBytes, let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let status = SystemNotificationHelperStatus(rawValue: envelope.status) else { return .failed }
        return SystemNotificationFetch(status: status, cursor: envelope.cursor ?? -1, items: Array((envelope.items ?? []).prefix(50)))
    }
}

struct SystemNotificationAppsFetch: Equatable, Sendable {
    var status: SystemNotificationHelperStatus
    var apps: [String]

    static let failed = SystemNotificationAppsFetch(status: .failed, apps: [])

    private struct Envelope: Decodable {
        var status: String
        var apps: [String]?
    }

    static func decode(_ data: Data) -> SystemNotificationAppsFetch {
        guard data.count <= SystemNotificationFetch.maxBytes, let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let status = SystemNotificationHelperStatus(rawValue: envelope.status) else { return .failed }
        return SystemNotificationAppsFetch(status: status, apps: Array((envelope.apps ?? []).prefix(500)))
    }
}

struct SystemNotificationBanner: Identifiable, Equatable {
    let id = UUID()
    let bundleID: String
    let appName: String
    let title: String
    let subtitle: String
    let body: String
}

enum SystemNotificationStatus: Equatable {
    case off
    case waiting
    case ready
    case noAccess
    case notFound
    case unsupported
    case failed
}
