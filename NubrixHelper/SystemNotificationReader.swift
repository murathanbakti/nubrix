import Foundation
import Darwin
import SQLite3

struct SystemNotificationItem: Codable {
    var id: Int64
    var bundleID: String
    var title: String
    var subtitle: String
    var body: String
    var date: Double
}

struct SystemNotificationResult: Codable {
    var status: String
    var cursor: Int64
    var items: [SystemNotificationItem]

    func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data(#"{"status":"failed","cursor":0,"items":[]}"#.utf8)
    }
}

struct SystemNotificationAppsResult: Codable {
    var status: String
    var apps: [String]

    func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data(#"{"status":"failed","apps":[]}"#.utf8)
    }
}

final class SystemNotificationReader {
    private struct FileStamp: Equatable {
        var mtimeSeconds: Int
        var mtimeNanos: Int
        var size: Int64
    }

    private struct Stamp: Equatable {
        var db: FileStamp
        var wal: FileStamp?
    }

    private enum Opened {
        case handle(OpaquePointer)
        case status(String)
    }

    private static let referenceOffset: Double = 978_307_200
    private static let batchLimit: Int32 = 50

    private var lastStamp: Stamp?
    private var lastCursor: Int64?
    private var deliveredMark: Double?
    private var hasDeliveredDate = true

    static func databasePath() -> String? {
        guard let home = ClaudeExecutableLocator.realHome() else { return nil }
        return home + "/Library/Group Containers/group.com.apple.usernoted/db2/db"
    }

    func fetch(after cursor: Int64, allowed: Set<String>) -> SystemNotificationResult {
        guard let path = Self.databasePath() else { return Self.failed(cursor) }
        let stamp: Stamp
        switch Self.stamp(path: path) {
        case .success(let value): stamp = value
        case .failure(let status): return Self.empty(status, cursor)
        }
        if cursor >= 0, stamp == lastStamp, lastCursor == cursor {
            return SystemNotificationResult(status: "ok", cursor: cursor, items: [])
        }
        let opened = Self.open(path: path)
        guard case .handle(let db) = opened else {
            if case .status(let status) = opened { return Self.empty(status, cursor) }
            return Self.failed(cursor)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 200)

        let result: SystemNotificationResult
        var full = false
        if cursor < 0 {
            deliveredMark = nil
            result = Self.currentMax(db: db)
            deliveredMark = maxDelivered(db: db)
        } else {
            if deliveredMark == nil { deliveredMark = maxDelivered(db: db) }
            let outcome = newItems(db: db, after: cursor, allowed: allowed)
            result = outcome.result
            full = outcome.full
        }
        if result.status == "ok", !full {
            lastStamp = stamp
            lastCursor = result.cursor
        } else {
            lastStamp = nil
            lastCursor = nil
        }
        return result
    }

    func apps() -> SystemNotificationAppsResult {
        guard let path = Self.databasePath() else { return SystemNotificationAppsResult(status: "failed", apps: []) }
        if case .failure(let status) = Self.stamp(path: path) {
            return SystemNotificationAppsResult(status: status, apps: [])
        }
        let opened = Self.open(path: path)
        guard case .handle(let db) = opened else {
            if case .status(let status) = opened { return SystemNotificationAppsResult(status: status, apps: []) }
            return SystemNotificationAppsResult(status: "failed", apps: [])
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 200)

        let sql = "SELECT DISTINCT a.identifier FROM app a WHERE EXISTS (SELECT 1 FROM record r WHERE r.app_id = a.app_id)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return SystemNotificationAppsResult(status: Self.statusForFailure(db), apps: [])
        }
        defer { sqlite3_finalize(statement) }
        var found = Set<String>()
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 0) {
                    let value = String(cString: text)
                    if !value.isEmpty, value.count <= 256 { found.insert(value) }
                }
            } else if step == SQLITE_DONE {
                break
            } else {
                return SystemNotificationAppsResult(status: Self.statusForFailure(db), apps: [])
            }
        }
        return SystemNotificationAppsResult(status: "ok", apps: found.sorted())
    }

    func exists(recID: Int64) -> Bool? {
        guard let path = Self.databasePath() else { return nil }
        if case .failure = Self.stamp(path: path) { return nil }
        guard case .handle(let db) = Self.open(path: path) else { return nil }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 200)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM record WHERE rec_id = ?1 LIMIT 1", -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, recID)
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: return nil
        }
    }

    func recordCount(bundleID: String) -> Int? {
        guard let path = Self.databasePath() else { return nil }
        if case .failure = Self.stamp(path: path) { return nil }
        guard case .handle(let db) = Self.open(path: path) else { return nil }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 200)
        var statement: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM record r JOIN app a ON a.app_id = r.app_id WHERE a.identifier = ?1"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, bundleID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func failed(_ cursor: Int64) -> SystemNotificationResult {
        empty("failed", cursor)
    }

    private static func empty(_ status: String, _ cursor: Int64) -> SystemNotificationResult {
        SystemNotificationResult(status: status, cursor: cursor, items: [])
    }

    private enum StampOutcome {
        case success(Stamp)
        case failure(String)
    }

    private static func stamp(path: String) -> StampOutcome {
        var info = stat()
        if stat(path, &info) != 0 {
            switch errno {
            case EPERM, EACCES: return .failure("noAccess")
            case ENOENT, ENOTDIR: return .failure("notFound")
            default: return .failure("failed")
            }
        }
        let db = FileStamp(mtimeSeconds: Int(info.st_mtimespec.tv_sec), mtimeNanos: Int(info.st_mtimespec.tv_nsec), size: Int64(info.st_size))
        var walInfo = stat()
        var wal: FileStamp?
        if stat(path + "-wal", &walInfo) == 0 {
            wal = FileStamp(mtimeSeconds: Int(walInfo.st_mtimespec.tv_sec), mtimeNanos: Int(walInfo.st_mtimespec.tv_nsec), size: Int64(walInfo.st_size))
        }
        return .success(Stamp(db: db, wal: wal))
    }

    private static func open(path: String) -> Opened {
        var db: OpaquePointer?
        let code = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard code == SQLITE_OK, let db else {
            let sysErrno = db.map { sqlite3_system_errno($0) } ?? 0
            if let db { sqlite3_close(db) }
            if sysErrno == EPERM || sysErrno == EACCES || code == SQLITE_PERM || code == SQLITE_AUTH { return .status("noAccess") }
            if sysErrno == ENOENT { return .status("notFound") }
            return .status("failed")
        }
        return .handle(db)
    }

    private static func statusForFailure(_ db: OpaquePointer) -> String {
        let code = sqlite3_errcode(db) & 0xFF
        switch code {
        case SQLITE_PERM, SQLITE_AUTH, SQLITE_CANTOPEN: return "noAccess"
        case SQLITE_BUSY, SQLITE_LOCKED, SQLITE_IOERR, SQLITE_NOMEM, SQLITE_INTERRUPT: return "failed"
        default: return "unsupported"
        }
    }

    private static func currentMax(db: OpaquePointer) -> SystemNotificationResult {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT MAX(rec_id) FROM record", -1, &statement, nil) == SQLITE_OK, let statement else {
            return empty(statusForFailure(db), -1)
        }
        defer { sqlite3_finalize(statement) }
        let step = sqlite3_step(statement)
        if step == SQLITE_ROW {
            return SystemNotificationResult(status: "ok", cursor: sqlite3_column_int64(statement, 0), items: [])
        }
        if step == SQLITE_DONE {
            return SystemNotificationResult(status: "ok", cursor: 0, items: [])
        }
        return empty(statusForFailure(db), -1)
    }

    private func maxDelivered(db: OpaquePointer) -> Double? {
        guard hasDeliveredDate else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COALESCE(MAX(delivered_date), 0) FROM record", -1, &statement, nil) == SQLITE_OK, let statement else {
            hasDeliveredDate = false
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_double(statement, 0)
    }

    private func newItems(db: OpaquePointer, after cursor: Int64, allowed: Set<String>) -> (result: SystemNotificationResult, full: Bool) {
        let mark = hasDeliveredDate ? deliveredMark : nil
        let sql: String
        if mark != nil {
            sql = "SELECT r.rec_id, a.identifier, r.data, COALESCE(r.delivered_date, 0) FROM record r JOIN app a ON a.app_id = r.app_id WHERE r.rec_id > ?1 OR COALESCE(r.delivered_date, 0) > ?3 ORDER BY COALESCE(r.delivered_date, 0) ASC, r.rec_id ASC LIMIT ?2"
        } else {
            sql = "SELECT r.rec_id, a.identifier, r.data, 0 FROM record r JOIN app a ON a.app_id = r.app_id WHERE r.rec_id > ?1 ORDER BY r.rec_id ASC LIMIT ?2"
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            if mark != nil {
                hasDeliveredDate = false
                deliveredMark = nil
                return newItems(db: db, after: cursor, allowed: allowed)
            }
            return (Self.empty(Self.statusForFailure(db), cursor), false)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, cursor)
        sqlite3_bind_int(statement, 2, Self.batchLimit)
        if let mark { sqlite3_bind_double(statement, 3, mark) }

        var maxID = cursor
        var maxDate = mark ?? 0
        var rows: Int32 = 0
        var items: [SystemNotificationItem] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { return (Self.empty(Self.statusForFailure(db), cursor), false) }
            rows += 1
            let id = sqlite3_column_int64(statement, 0)
            if id > maxID { maxID = id }
            let delivered = sqlite3_column_double(statement, 3)
            if delivered > maxDate { maxDate = delivered }
            guard !allowed.isEmpty, let idText = sqlite3_column_text(statement, 1) else { continue }
            let bundleID = String(cString: idText)
            guard allowed.contains(bundleID) else { continue }
            let length = Int(sqlite3_column_bytes(statement, 2))
            guard length > 0, length <= 1_000_000, let blob = sqlite3_column_blob(statement, 2) else { continue }
            let data = Data(bytes: blob, count: length)
            if let item = Self.parse(id: id, bundleID: bundleID, data: data) { items.append(item) }
        }
        if mark != nil { deliveredMark = maxDate }
        return (SystemNotificationResult(status: "ok", cursor: maxID, items: items), rows >= Self.batchLimit)
    }

    private static func parse(id: Int64, bundleID: String, data: Data) -> SystemNotificationItem? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let root = plist as? [String: Any] else { return nil }
        let req = root["req"] as? [String: Any] ?? [:]
        let title = sanitize(req["titl"] as? String, limit: 120)
        let subtitle = sanitize(req["subt"] as? String, limit: 120)
        let body = sanitize(req["body"] as? String, limit: 400)
        guard !title.isEmpty || !body.isEmpty else { return nil }
        var date = Date().timeIntervalSince1970
        if let seconds = root["date"] as? Double, seconds.isFinite {
            date = seconds + referenceOffset
        }
        return SystemNotificationItem(id: id, bundleID: bundleID, title: title, subtitle: subtitle, body: body, date: date)
    }

    static func sanitize(_ value: String?, limit: Int) -> String {
        guard let value else { return "" }
        var output = String.UnicodeScalarView()
        var lastWasSpace = true
        for scalar in value.unicodeScalars {
            if isInvisible(scalar) { continue }
            if scalar.properties.isWhitespace || scalar == "\n" || scalar == "\r" || scalar == "\t" {
                if !lastWasSpace {
                    output.append(" ")
                    lastWasSpace = true
                }
                continue
            }
            if scalar.properties.generalCategory == .control { continue }
            output.append(scalar)
            lastWasSpace = false
        }
        var text = String(output)
        if text.hasSuffix(" ") { text.removeLast() }
        if text.count > limit { text = String(text.prefix(limit)) }
        return text
    }

    private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200B, 0x200E...0x200F, 0x202A...0x202E, 0x2066...0x2069, 0xFEFF: return true
        default: return false
        }
    }
}
