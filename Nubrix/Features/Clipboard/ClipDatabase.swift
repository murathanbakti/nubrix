import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum ClipDatabaseError: Error {
    case open(String)
    case statement(String)
}

final class ClipDatabase: @unchecked Sendable {
    static let previewLength = 300
    static let schemaVersion: Int32 = 1

    let directory: URL
    private var db: OpaquePointer?

    static func thumbnailName(for imageFile: String) -> String {
        let base = (imageFile as NSString).deletingPathExtension
        return base + ".thumb.png"
    }

    init(directory: URL) throws {
        self.directory = directory
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let path = directory.appendingPathComponent("vitrin.sqlite").path
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(db)
            db = nil
            throw ClipDatabaseError.open(message)
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        Self.excludeFromBackup(directory)
        try exec("PRAGMA journal_mode=WAL")
        try exec("PRAGMA secure_delete=ON")
        try exec("PRAGMA synchronous=NORMAL")
        try migrate()
        for suffix in ["-wal", "-shm"] {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path + suffix)
        }
    }

    deinit {
        sqlite3_close(db)
    }

    static func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }

    var isExcludedFromBackup: Bool {
        (try? directory.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup ?? false
    }

    private func migrate() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS clips(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind INTEGER NOT NULL,
            content TEXT,
            preview TEXT,
            text_len INTEGER NOT NULL DEFAULT 0,
            image_file TEXT,
            image_w INTEGER NOT NULL DEFAULT 0,
            image_h INTEGER NOT NULL DEFAULT 0,
            hash TEXT NOT NULL,
            source TEXT,
            created REAL NOT NULL,
            used REAL NOT NULL,
            pinned INTEGER NOT NULL DEFAULT 0
        )
        """)
        let existing = try columnNames(of: "clips")
        if !existing.contains("preview") {
            try exec("ALTER TABLE clips ADD COLUMN preview TEXT")
        }
        if !existing.contains("text_len") {
            try exec("ALTER TABLE clips ADD COLUMN text_len INTEGER NOT NULL DEFAULT 0")
        }
        try exec("CREATE UNIQUE INDEX IF NOT EXISTS clips_hash ON clips(hash)")
        try exec("CREATE INDEX IF NOT EXISTS clips_used ON clips(used)")
        try exec("""
        CREATE VIRTUAL TABLE IF NOT EXISTS clips_fts USING fts5(
            content, content='clips', content_rowid='id', tokenize='unicode61 remove_diacritics 2'
        )
        """)
        try exec("""
        CREATE TRIGGER IF NOT EXISTS clips_ai AFTER INSERT ON clips BEGIN
            INSERT INTO clips_fts(rowid, content) VALUES (new.id, COALESCE(new.content, ''));
        END
        """)
        try exec("""
        CREATE TRIGGER IF NOT EXISTS clips_ad AFTER DELETE ON clips BEGIN
            INSERT INTO clips_fts(clips_fts, rowid, content) VALUES ('delete', old.id, COALESCE(old.content, ''));
        END
        """)
    }

    private func columnNames(of table: String) throws -> Set<String> {
        let stmt = try prepare("PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(stmt) }
        var names = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = Self.text(stmt, 1) { names.insert(name) }
        }
        return names
    }

    var userVersion: Int32 {
        Int32((try? scalarInt("PRAGMA user_version")) ?? 0)
    }

    @discardableResult
    func runDeferredMigration() -> Bool {
        guard userVersion < Self.schemaVersion else { return false }
        _ = try? run("UPDATE clips SET preview = substr(content, 1, ?), text_len = length(content) WHERE content IS NOT NULL AND preview IS NULL", [Self.previewLength])
        _ = try? exec("INSERT INTO clips_fts(clips_fts, rank) VALUES('secure-delete', 1)")
        _ = try? exec("INSERT INTO clips_fts(clips_fts) VALUES('rebuild')")
        checkpoint()
        _ = try? exec("PRAGMA user_version = \(Self.schemaVersion)")
        return true
    }

    func checkpoint() {
        _ = try? exec("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    private func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(error)
            throw ClipDatabaseError.statement(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw ClipDatabaseError.statement(String(cString: sqlite3_errmsg(db)))
        }
        return stmt!
    }

    private func bind(_ stmt: OpaquePointer, _ values: [Any?]) {
        for (i, value) in values.enumerated() {
            let idx = Int32(i + 1)
            switch value {
            case nil: sqlite3_bind_null(stmt, idx)
            case let v as String: sqlite3_bind_text(stmt, idx, v, -1, sqliteTransient)
            case let v as Int: sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Int64: sqlite3_bind_int64(stmt, idx, v)
            case let v as Double: sqlite3_bind_double(stmt, idx, v)
            case let v as Bool: sqlite3_bind_int(stmt, idx, v ? 1 : 0)
            default: sqlite3_bind_null(stmt, idx)
            }
        }
    }

    private func run(_ sql: String, _ values: [Any?] = []) throws {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, values)
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            throw ClipDatabaseError.statement(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func query(_ sql: String, _ values: [Any?] = []) throws -> [ClipItem] {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, values)
        var out: [ClipItem] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                out.append(Self.row(stmt))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw ClipDatabaseError.statement(String(cString: sqlite3_errmsg(db)))
            }
        }
        return out
    }

    private static let columns = "clips.id, clips.kind, clips.preview, clips.text_len, clips.image_file, clips.image_w, clips.image_h, clips.source, clips.created, clips.used, clips.pinned"

    private static func text(_ stmt: OpaquePointer, _ col: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: c)
    }

    private static func row(_ stmt: OpaquePointer) -> ClipItem {
        ClipItem(
            id: sqlite3_column_int64(stmt, 0),
            kind: ClipKind(rawValue: Int(sqlite3_column_int(stmt, 1))) ?? .text,
            preview: text(stmt, 2),
            textLength: Int(sqlite3_column_int64(stmt, 3)),
            imageFile: text(stmt, 4),
            imageWidth: Int(sqlite3_column_int(stmt, 5)),
            imageHeight: Int(sqlite3_column_int(stmt, 6)),
            sourceApp: text(stmt, 7),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8)),
            lastUsedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9)),
            pinned: sqlite3_column_int(stmt, 10) != 0
        )
    }

    private func scalarInt(_ sql: String, _ values: [Any?] = []) throws -> Int64? {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, values)
        if sqlite3_step(stmt) == SQLITE_ROW { return sqlite3_column_int64(stmt, 0) }
        return nil
    }

    private func scalarText(_ sql: String, _ values: [Any?] = []) -> String? {
        guard let stmt = try? prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, values)
        if sqlite3_step(stmt) == SQLITE_ROW { return Self.text(stmt, 0) }
        return nil
    }

    private func textColumn(_ sql: String, _ values: [Any?] = []) -> [String] {
        guard let stmt = try? prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, values)
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let value = Self.text(stmt, 0) { out.append(value) }
        }
        return out
    }

    var lastInsertedID: Int64 { sqlite3_last_insert_rowid(db) }

    func writeImage(png: Data, thumbnail: Data) throws -> String {
        let name = UUID().uuidString + ".png"
        try write(png, named: name)
        try write(thumbnail, named: Self.thumbnailName(for: name))
        return name
    }

    private func write(_ data: Data, named name: String) throws {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func removeFiles(_ imageFiles: [String]) {
        let fm = FileManager.default
        for file in imageFiles {
            try? fm.removeItem(at: directory.appendingPathComponent(file))
            try? fm.removeItem(at: directory.appendingPathComponent(Self.thumbnailName(for: file)))
        }
    }

    func id(forHash hash: String) -> Int64? {
        try? scalarInt("SELECT id FROM clips WHERE hash = ?", [hash])
    }

    @discardableResult
    func touch(id: Int64, now: Date = Date()) -> Bool {
        (try? run("UPDATE clips SET used = ? WHERE id = ?", [now.timeIntervalSince1970, id])) != nil
    }

    func insert(kind: ClipKind, content: String?, imageFile: String?, width: Int, height: Int, hash: String, source: String?, now: Date = Date()) throws -> Int64 {
        var preview: String?
        var length = 0
        if let content {
            let scalars = content.unicodeScalars
            preview = String(String.UnicodeScalarView(scalars.prefix(Self.previewLength)))
            length = scalars.count
        }
        try run(
            "INSERT INTO clips(kind, content, preview, text_len, image_file, image_w, image_h, hash, source, created, used, pinned) VALUES (?,?,?,?,?,?,?,?,?,?,?,0)",
            [kind.rawValue, content, preview, length, imageFile, width, height, hash, source, now.timeIntervalSince1970, now.timeIntervalSince1970]
        )
        return lastInsertedID
    }

    func fullText(id: Int64, maxChars: Int? = nil) -> String? {
        if let maxChars {
            return scalarText("SELECT substr(content, 1, ?) FROM clips WHERE id = ?", [maxChars, id])
        }
        return scalarText("SELECT content FROM clips WHERE id = ?", [id])
    }

    func imageFile(id: Int64) -> String? {
        scalarText("SELECT image_file FROM clips WHERE id = ?", [id])
    }

    func summary(id: Int64) -> ClipItem? {
        (try? query("SELECT \(Self.columns) FROM clips WHERE id = ?", [id]))?.first
    }

    func summaries(limit: Int = 1000) -> [ClipItem] {
        (try? query("SELECT \(Self.columns) FROM clips ORDER BY used DESC, id DESC LIMIT ?", [limit])) ?? []
    }

    static func ftsQuery(_ raw: String) -> String? {
        let tokens = raw.split(whereSeparator: { $0.isWhitespace }).map { token -> String in
            let cleaned = token.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(cleaned)\"*"
        }
        return tokens.isEmpty ? nil : tokens.joined(separator: " ")
    }

    func search(_ raw: String, limit: Int = 300) -> [ClipItem] {
        guard let match = Self.ftsQuery(raw) else { return summaries(limit: limit) }
        let sql = "SELECT \(Self.columns) FROM clips JOIN clips_fts ON clips_fts.rowid = clips.id WHERE clips_fts MATCH ? ORDER BY clips.used DESC, clips.id DESC LIMIT ?"
        return (try? query(sql, [match, limit])) ?? []
    }

    func setPinned(id: Int64, _ pinned: Bool) {
        try? run("UPDATE clips SET pinned = ? WHERE id = ?", [pinned, id])
    }

    func delete(id: Int64) {
        let file = imageFile(id: id)
        try? run("DELETE FROM clips WHERE id = ?", [id])
        if let file { removeFiles([file]) }
        checkpoint()
    }

    private func imageFiles(where clause: String, _ values: [Any?]) -> [String] {
        textColumn("SELECT image_file FROM clips WHERE image_file IS NOT NULL AND \(clause)", values)
    }

    @discardableResult
    func expire(olderThan cutoff: Date) -> Int {
        let files = imageFiles(where: "pinned = 0 AND used < ?", [cutoff.timeIntervalSince1970])
        let before = (try? scalarInt("SELECT COUNT(*) FROM clips")) ?? 0
        try? run("DELETE FROM clips WHERE pinned = 0 AND used < ?", [cutoff.timeIntervalSince1970])
        removeFiles(files)
        let removed = Int(before - ((try? scalarInt("SELECT COUNT(*) FROM clips")) ?? 0))
        if removed > 0 { checkpoint() }
        return removed
    }

    @discardableResult
    func trim(maxUnpinned: Int) -> Int {
        let files = imageFiles(where: "pinned = 0 AND id NOT IN (SELECT id FROM clips WHERE pinned = 0 ORDER BY used DESC, id DESC LIMIT ?)", [maxUnpinned])
        let before = (try? scalarInt("SELECT COUNT(*) FROM clips")) ?? 0
        try? run("DELETE FROM clips WHERE pinned = 0 AND id NOT IN (SELECT id FROM clips WHERE pinned = 0 ORDER BY used DESC, id DESC LIMIT ?)", [maxUnpinned])
        removeFiles(files)
        let removed = Int(before - ((try? scalarInt("SELECT COUNT(*) FROM clips")) ?? 0))
        if removed > 0 { checkpoint() }
        return removed
    }

    func clear(keepPinned: Bool) {
        let files = imageFiles(where: keepPinned ? "pinned = 0" : "1 = 1", [])
        try? run(keepPinned ? "DELETE FROM clips WHERE pinned = 0" : "DELETE FROM clips")
        removeFiles(files)
        checkpoint()
    }

    func count() -> Int {
        Int((try? scalarInt("SELECT COUNT(*) FROM clips")) ?? 0)
    }
}
