import Foundation
import os
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private let clipLog = Logger(subsystem: "dev.nubrix.app", category: "vitrin")

enum ClipDatabaseError: Error {
    case open(String)
    case statement(String)
    case noCipher
}

enum ClipMigrationFaultPoint {
    case beforeCommit
    case afterCommit
}

final class ClipDatabase: @unchecked Sendable {
    static let previewLength = 300
    static let schemaVersion: Int32 = 3

    let directory: URL
    private var db: OpaquePointer?
    private var searchIndex: ClipSearchIndex?

    private(set) var cipher: ClipCipher?
    private(set) var imageVault: ClipImageVault?

    var migrationFault: ((ClipMigrationFaultPoint) throws -> Void)?

    static func thumbnailName(for imageFile: String) -> String {
        let name = imageFile as NSString
        let ext = name.pathExtension
        return name.deletingPathExtension + ".thumb." + (ext.isEmpty ? "png" : ext)
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
        try exec("PRAGMA temp_store=MEMORY")
        try migrate()
        for suffix in ["-wal", "-shm"] {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path + suffix)
        }
    }

    deinit {
        if let db { sqlite3_close_v2(db) }
    }

    func install(_ cipher: ClipCipher) {
        self.cipher = cipher
        imageVault = ClipImageVault(directory: directory, cipher: cipher)
    }

    func close() {
        searchIndex = nil
        if let handle = db {
            sqlite3_close_v2(handle)
        }
        db = nil
    }

    var storedKeyID: String? {
        scalarText("SELECT v FROM meta WHERE k = 'key_id'")
    }

    func setKeyID(_ id: String) throws {
        try run("INSERT OR REPLACE INTO meta(k, v) VALUES ('key_id', ?)", [id])
    }

    var encryptedRowCount: Int {
        Int((try? scalarInt("SELECT COUNT(*) FROM clips WHERE enc = 1")) ?? 0)
    }

    var plaintextRowCount: Int {
        Int((try? scalarInt("SELECT COUNT(*) FROM clips WHERE enc = 0")) ?? 0)
    }

    var hasSearchIndex: Bool { searchIndex != nil }

    var isOpen: Bool { db != nil }

    func dropSearchIndex() {
        searchIndex = nil
    }

    func textHash(_ text: String) -> String? {
        cipher?.keyedHash(text: text)
    }

    func imageHash(_ png: Data) -> String? {
        cipher?.keyedHash(png)
    }

    static func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }

    var isExcludedFromBackup: Bool {
        var url = directory
        url.removeAllCachedResourceValues()
        return (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup ?? false
    }

    private func migrate() throws {
        let existed = (try scalarInt("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'clips'") ?? 0) > 0
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
            pinned INTEGER NOT NULL DEFAULT 0,
            enc INTEGER NOT NULL DEFAULT 0,
            content_enc BLOB,
            preview_enc BLOB,
            source_enc BLOB
        )
        """)
        let existing = try columnNames(of: "clips")
        if !existing.contains("preview") {
            try exec("ALTER TABLE clips ADD COLUMN preview TEXT")
        }
        if !existing.contains("text_len") {
            try exec("ALTER TABLE clips ADD COLUMN text_len INTEGER NOT NULL DEFAULT 0")
        }
        if !existing.contains("bytes") {
            try exec("ALTER TABLE clips ADD COLUMN bytes INTEGER NOT NULL DEFAULT 0")
        }
        if !existing.contains("enc") {
            try exec("ALTER TABLE clips ADD COLUMN enc INTEGER NOT NULL DEFAULT 0")
        }
        for column in ["content_enc", "preview_enc", "source_enc"] where !existing.contains(column) {
            try exec("ALTER TABLE clips ADD COLUMN \(column) BLOB")
        }
        try exec("CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v BLOB)")
        try exec("CREATE UNIQUE INDEX IF NOT EXISTS clips_hash ON clips(hash)")
        try exec("CREATE INDEX IF NOT EXISTS clips_used ON clips(used)")
        try exec("CREATE INDEX IF NOT EXISTS clips_unpinned_used ON clips(pinned, used DESC, id DESC)")
        if !existed {
            try exec("PRAGMA user_version = \(Self.schemaVersion)")
        }
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
        let current = userVersion
        var ok = true
        if current < 1 {
            do {
                try run("UPDATE clips SET preview = substr(content, 1, ?), text_len = length(content) WHERE content IS NOT NULL AND preview IS NULL", [Self.previewLength])
            } catch {
                clipLog.error("Vitrin preview backfill failed: \(String(describing: error), privacy: .public)")
                ok = false
            }
        }
        if current < 2, !backfillBytes() { ok = false }
        if current < 3 {
            do {
                try dropLegacyFTS()
            } catch {
                clipLog.error("Vitrin could not drop the legacy search index: \(String(describing: error), privacy: .public)")
                ok = false
            }
        }
        sweepOrphans()
        return ok
    }

    private func dropLegacyFTS() throws {
        try exec("DROP TRIGGER IF EXISTS clips_ai")
        try exec("DROP TRIGGER IF EXISTS clips_ad")
        try exec("DROP TABLE IF EXISTS clips_fts")
    }

    private var hasLegacyFTS: Bool {
        ((try? scalarInt("SELECT COUNT(*) FROM sqlite_master WHERE name IN ('clips_ai', 'clips_ad', 'clips_fts')")) ?? 0) > 0
    }

    @discardableResult
    func sweepOrphans() -> Int {
        var referenced = Set<String>()
        for file in textColumn("SELECT image_file FROM clips WHERE image_file IS NOT NULL") {
            referenced.insert(file)
            referenced.insert(Self.thumbnailName(for: file))
        }
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var removed = 0
        for name in names {
            let ext = (name as NSString).pathExtension.lowercased()
            guard ext == "png" || ext == "vimg", !referenced.contains(name) else { continue }
            if (try? fm.removeItem(at: directory.appendingPathComponent(name))) != nil { removed += 1 }
        }
        return removed
    }

    private func backfillBytes() -> Bool {
        do {
            try exec("BEGIN")
            try run("UPDATE clips SET bytes = length(CAST(content AS BLOB)) WHERE content IS NOT NULL AND bytes = 0")
            let stmt = try prepare("SELECT id, image_file FROM clips WHERE image_file IS NOT NULL AND bytes = 0")
            var rows: [(Int64, String)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let file = Self.text(stmt, 1) { rows.append((sqlite3_column_int64(stmt, 0), file)) }
            }
            sqlite3_finalize(stmt)
            for (id, file) in rows {
                let size = fileSize(file) + fileSize(Self.thumbnailName(for: file))
                try run("UPDATE clips SET bytes = ? WHERE id = ?", [size, id])
            }
            try exec("COMMIT")
            return true
        } catch {
            try? exec("ROLLBACK")
            clipLog.error("Vitrin size backfill failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private func fileSize(_ name: String) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }

    func checkpoint() {
        _ = try? exec("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    private func exec(_ sql: String) throws {
        guard db != nil else { throw ClipDatabaseError.statement("database closed") }
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(error)
            throw ClipDatabaseError.statement(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard db != nil else { throw ClipDatabaseError.statement("database closed") }
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
            case let v as Data:
                if v.isEmpty {
                    sqlite3_bind_zeroblob(stmt, idx, 0)
                } else {
                    _ = v.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(v.count), sqliteTransient) }
                }
            case let v as String: _ = v.withCString { sqlite3_bind_text(stmt, idx, $0, Int32(v.utf8.count), sqliteTransient) }
            case let v as Int: sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Int64: sqlite3_bind_int64(stmt, idx, v)
            case let v as Double: sqlite3_bind_double(stmt, idx, v)
            case let v as Bool: sqlite3_bind_int(stmt, idx, v ? 1 : 0)
            default: sqlite3_bind_null(stmt, idx)
            }
        }
    }

    @discardableResult
    private func run(_ sql: String, _ values: [Any?] = []) throws -> Int {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, values)
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            throw ClipDatabaseError.statement(String(cString: sqlite3_errmsg(db)))
        }
        return Int(sqlite3_changes(db))
    }

    private func query(_ sql: String, _ values: [Any?] = []) throws -> [ClipItem] {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, values)
        var out: [ClipItem] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                out.append(row(stmt))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw ClipDatabaseError.statement(String(cString: sqlite3_errmsg(db)))
            }
        }
        return out
    }

    private static let columns = "clips.id, clips.kind, clips.preview, clips.text_len, clips.image_file, clips.image_w, clips.image_h, clips.source, clips.created, clips.used, clips.pinned, clips.enc, clips.preview_enc, clips.source_enc, clips.hash"

    private static func text(_ stmt: OpaquePointer, _ col: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, col) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, col))
        return String(decoding: UnsafeBufferPointer(start: UnsafeRawPointer(c).assumingMemoryBound(to: UInt8.self), count: count), as: UTF8.self)
    }

    private static func blob(_ stmt: OpaquePointer, _ col: Int32) -> Data? {
        guard sqlite3_column_type(stmt, col) != SQLITE_NULL else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, col))
        guard count > 0, let bytes = sqlite3_column_blob(stmt, col) else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    private func row(_ stmt: OpaquePointer) -> ClipItem {
        var preview = Self.text(stmt, 2)
        var source = Self.text(stmt, 7)
        if sqlite3_column_int(stmt, 11) != 0 {
            preview = nil
            source = nil
            if let cipher, let hash = Self.text(stmt, 14) {
                if let sealed = Self.blob(stmt, 12) {
                    preview = try? cipher.openString(sealed, aad: ClipCipher.fieldAAD("preview", hash: hash))
                }
                if let sealed = Self.blob(stmt, 13) {
                    source = try? cipher.openString(sealed, aad: ClipCipher.fieldAAD("source", hash: hash))
                }
            }
        }
        return ClipItem(
            id: sqlite3_column_int64(stmt, 0),
            kind: ClipKind(rawValue: Int(sqlite3_column_int(stmt, 1))) ?? .text,
            preview: preview,
            textLength: Int(sqlite3_column_int64(stmt, 3)),
            imageFile: Self.text(stmt, 4),
            imageWidth: Int(sqlite3_column_int(stmt, 5)),
            imageHeight: Int(sqlite3_column_int(stmt, 6)),
            sourceApp: source,
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

    var lastInsertedID: Int64 { db.map { sqlite3_last_insert_rowid($0) } ?? 0 }

    func writeImage(png: Data, thumbnail: Data) throws -> String {
        guard let imageVault else { throw ClipDatabaseError.noCipher }
        let name = UUID().uuidString + ".vimg"
        let thumbName = Self.thumbnailName(for: name)
        try imageVault.write(png, named: name)
        do {
            try imageVault.write(thumbnail, named: thumbName)
        } catch {
            removeFiles([name])
            throw error
        }
        return name
    }

    func imageData(named name: String) -> Data? {
        imageVault?.read(named: name)
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
        guard (try? run("UPDATE clips SET used = ? WHERE id = ?", [now.timeIntervalSince1970, id])) != nil else { return false }
        searchIndex?.touch(id: id, used: now.timeIntervalSince1970)
        return true
    }

    func insert(kind: ClipKind, content: String?, imageFile: String?, width: Int, height: Int, hash: String, source: String?, bytes: Int = 0, now: Date = Date()) throws -> Int64 {
        guard let cipher else { throw ClipDatabaseError.noCipher }
        var preview: String?
        var length = 0
        var size = bytes
        if let content {
            let scalars = content.unicodeScalars
            preview = String(String.UnicodeScalarView(scalars.prefix(Self.previewLength)))
            length = scalars.count
            size += content.utf8.count
        }
        let contentEnc = try content.map { try cipher.sealString($0, aad: ClipCipher.fieldAAD("content", hash: hash)) }
        let previewEnc = try preview.map { try cipher.sealString($0, aad: ClipCipher.fieldAAD("preview", hash: hash)) }
        let sourceEnc = try source.map { try cipher.sealString($0, aad: ClipCipher.fieldAAD("source", hash: hash)) }
        let stamp = now.timeIntervalSince1970
        try run(
            "INSERT INTO clips(kind, content, preview, text_len, image_file, image_w, image_h, hash, source, created, used, pinned, bytes, enc, content_enc, preview_enc, source_enc) VALUES (?,NULL,NULL,?,?,?,?,?,NULL,?,?,0,?,1,?,?,?)",
            [kind.rawValue, length, imageFile, width, height, hash, stamp, stamp, size, contentEnc, previewEnc, sourceEnc]
        )
        let id = lastInsertedID
        if let content, kind != .image { searchIndex?.insert(id: id, used: stamp, text: content) }
        return id
    }

    func fullText(id: Int64, maxChars: Int? = nil) -> String? {
        guard let text = plainContent(id: id) else { return nil }
        guard let maxChars else { return text }
        return String(String.UnicodeScalarView(text.unicodeScalars.prefix(maxChars)))
    }

    private func plainContent(id: Int64) -> String? {
        guard let stmt = try? prepare("SELECT enc, content, content_enc, hash FROM clips WHERE id = ?") else { return nil }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, [id])
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return decodedContent(stmt, enc: 0, content: 1, sealed: 2, hash: 3)
    }

    private func decodedContent(_ stmt: OpaquePointer, enc: Int32, content: Int32, sealed: Int32, hash: Int32) -> String? {
        if sqlite3_column_int(stmt, enc) == 0 { return Self.text(stmt, content) }
        guard let cipher, let hash = Self.text(stmt, hash), let data = Self.blob(stmt, sealed) else { return nil }
        return try? cipher.openString(data, aad: ClipCipher.fieldAAD("content", hash: hash))
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

    func search(_ raw: String, limit: Int = 300) -> [ClipItem] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return summaries(limit: limit) }
        let ids = ensureSearchIndex().search(trimmed, limit: limit)
        guard !ids.isEmpty else { return [] }
        var found: [Int64: ClipItem] = [:]
        var start = 0
        while start < ids.count {
            let chunk = Array(ids[start..<min(start + 500, ids.count)])
            start += chunk.count
            let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            for item in (try? query("SELECT \(Self.columns) FROM clips WHERE id IN (\(marks))", chunk)) ?? [] {
                found[item.id] = item
            }
        }
        return ids.compactMap { found[$0] }
    }

    private func ensureSearchIndex() -> ClipSearchIndex {
        if let searchIndex { return searchIndex }
        let index = ClipSearchIndex()
        if let stmt = try? prepare("SELECT id, used, enc, content, content_enc, hash FROM clips WHERE kind != ?") {
            bind(stmt, [ClipKind.image.rawValue])
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let text = decodedContent(stmt, enc: 2, content: 3, sealed: 4, hash: 5) {
                    index.insert(id: sqlite3_column_int64(stmt, 0), used: sqlite3_column_double(stmt, 1), text: text)
                }
            }
            sqlite3_finalize(stmt)
        }
        searchIndex = index
        return index
    }

    func setPinned(id: Int64, _ pinned: Bool) {
        _ = try? run("UPDATE clips SET pinned = ? WHERE id = ?", [pinned, id])
    }

    func delete(id: Int64) {
        let file = imageFile(id: id)
        _ = try? run("DELETE FROM clips WHERE id = ?", [id])
        searchIndex?.remove(id: id)
        if let file { removeFiles([file]) }
        checkpoint()
    }

    private func imageFiles(where clause: String, _ values: [Any?]) -> [String] {
        textColumn("SELECT image_file FROM clips WHERE image_file IS NOT NULL AND \(clause)", values)
    }

    @discardableResult
    func expire(olderThan cutoff: Date) -> Int {
        let files = imageFiles(where: "pinned = 0 AND used < ?", [cutoff.timeIntervalSince1970])
        guard let removed = try? run("DELETE FROM clips WHERE pinned = 0 AND used < ?", [cutoff.timeIntervalSince1970]) else { return 0 }
        removeFiles(files)
        if removed > 0 {
            searchIndex = nil
            checkpoint()
        }
        return removed
    }

    @discardableResult
    func trim(maxUnpinned: Int) -> Int {
        let files = imageFiles(where: "pinned = 0 AND id NOT IN (SELECT id FROM clips WHERE pinned = 0 ORDER BY used DESC, id DESC LIMIT ?)", [maxUnpinned])
        guard let removed = try? run("DELETE FROM clips WHERE pinned = 0 AND id NOT IN (SELECT id FROM clips WHERE pinned = 0 ORDER BY used DESC, id DESC LIMIT ?)", [maxUnpinned]) else { return 0 }
        removeFiles(files)
        if removed > 0 {
            searchIndex = nil
            checkpoint()
        }
        return removed
    }

    var totalBytes: Int64 {
        (try? scalarInt("SELECT COALESCE(SUM(bytes), 0) FROM clips")) ?? 0
    }

    @discardableResult
    func trim(maxBytes: Int64) -> Int {
        var excess = totalBytes - maxBytes
        guard excess > 0 else { return 0 }
        var removed = 0
        while excess > 0 {
            guard let stmt = try? prepare("SELECT id, bytes, image_file FROM clips WHERE pinned = 0 ORDER BY used ASC, id ASC LIMIT 64") else { break }
            var batch: [(id: Int64, bytes: Int64, file: String?)] = []
            var planned: Int64 = 0
            while planned < excess, sqlite3_step(stmt) == SQLITE_ROW {
                let size = sqlite3_column_int64(stmt, 1)
                batch.append((sqlite3_column_int64(stmt, 0), size, Self.text(stmt, 2)))
                planned += size
            }
            sqlite3_finalize(stmt)
            if batch.isEmpty { break }
            var deleted: [String] = []
            var freed: Int64 = 0
            var batchRemoved = 0
            for row in batch {
                guard let n = try? run("DELETE FROM clips WHERE id = ?", [row.id]) else { continue }
                batchRemoved += n
                freed += row.bytes
                if let file = row.file { deleted.append(file) }
            }
            removeFiles(deleted)
            removed += batchRemoved
            if batchRemoved == 0 { break }
            excess -= freed
        }
        if removed > 0 {
            searchIndex = nil
            checkpoint()
        }
        return removed
    }

    func clear(keepPinned: Bool) {
        let files = imageFiles(where: keepPinned ? "pinned = 0" : "1 = 1", [])
        _ = try? run(keepPinned ? "DELETE FROM clips WHERE pinned = 0" : "DELETE FROM clips")
        removeFiles(files)
        searchIndex = nil
        checkpoint()
    }

    private struct MigrationRow {
        let id: Int64
        let kind: Int
        let content: String?
        let preview: String?
        let source: String?
        let imageFile: String?
        let pinned: Int
        let used: Double
        let created: Double
    }

    private struct MigratedRow {
        let id: Int64
        let drop: Bool
        let hash: String
        let contentEnc: Data?
        let previewEnc: Data?
        let sourceEnc: Data?
        let newImage: String?
        let oldFiles: [String]
        let newFiles: [String]
        let pinned: Int
        let used: Double
        let created: Double
    }

    func migrateEncryptionBatch(limit: Int = 200) throws -> Bool {
        guard let cipher, let imageVault else { throw ClipDatabaseError.noCipher }
        if hasLegacyFTS { try dropLegacyFTS() }

        var pending: [MigrationRow] = []
        do {
            let stmt = try prepare("SELECT id, kind, content, preview, source, image_file, pinned, used, created FROM clips WHERE enc = 0 ORDER BY id LIMIT ?")
            defer { sqlite3_finalize(stmt) }
            bind(stmt, [limit])
            while sqlite3_step(stmt) == SQLITE_ROW {
                pending.append(MigrationRow(
                    id: sqlite3_column_int64(stmt, 0),
                    kind: Int(sqlite3_column_int(stmt, 1)),
                    content: Self.text(stmt, 2),
                    preview: Self.text(stmt, 3),
                    source: Self.text(stmt, 4),
                    imageFile: Self.text(stmt, 5),
                    pinned: Int(sqlite3_column_int(stmt, 6)),
                    used: sqlite3_column_double(stmt, 7),
                    created: sqlite3_column_double(stmt, 8)
                ))
            }
        }
        if pending.isEmpty { return false }

        let fm = FileManager.default
        var written: [String] = []
        var prepared: [MigratedRow] = []
        do {
            for row in pending {
                if row.kind == ClipKind.image.rawValue {
                    guard let file = row.imageFile else {
                        prepared.append(MigratedRow(id: row.id, drop: true, hash: "", contentEnc: nil, previewEnc: nil, sourceEnc: nil, newImage: nil, oldFiles: [], newFiles: [], pinned: row.pinned, used: row.used, created: row.created))
                        continue
                    }
                    let thumbFile = Self.thumbnailName(for: file)
                    guard let png = try? Data(contentsOf: directory.appendingPathComponent(file)) else {
                        prepared.append(MigratedRow(id: row.id, drop: true, hash: "", contentEnc: nil, previewEnc: nil, sourceEnc: nil, newImage: nil, oldFiles: [file, thumbFile], newFiles: [], pinned: row.pinned, used: row.used, created: row.created))
                        continue
                    }
                    let hash = cipher.keyedHash(png)
                    let base = (file as NSString).deletingPathExtension
                    let newName = base + ".vimg"
                    let newThumb = Self.thumbnailName(for: newName)
                    try imageVault.write(png, named: newName)
                    written.append(newName)
                    var newFiles = [newName]
                    if let thumb = try? Data(contentsOf: directory.appendingPathComponent(thumbFile)) {
                        try imageVault.write(thumb, named: newThumb)
                        written.append(newThumb)
                        newFiles.append(newThumb)
                    }
                    let sourceEnc = try row.source.map { try cipher.sealString($0, aad: ClipCipher.fieldAAD("source", hash: hash)) }
                    prepared.append(MigratedRow(id: row.id, drop: false, hash: hash, contentEnc: nil, previewEnc: nil, sourceEnc: sourceEnc, newImage: newName, oldFiles: [file, thumbFile], newFiles: newFiles, pinned: row.pinned, used: row.used, created: row.created))
                } else {
                    guard let content = row.content else {
                        prepared.append(MigratedRow(id: row.id, drop: true, hash: "", contentEnc: nil, previewEnc: nil, sourceEnc: nil, newImage: nil, oldFiles: row.imageFile.map { [$0, Self.thumbnailName(for: $0)] } ?? [], newFiles: [], pinned: row.pinned, used: row.used, created: row.created))
                        continue
                    }
                    let hash = cipher.keyedHash(text: content)
                    let preview = row.preview ?? String(String.UnicodeScalarView(content.unicodeScalars.prefix(Self.previewLength)))
                    let contentEnc = try cipher.sealString(content, aad: ClipCipher.fieldAAD("content", hash: hash))
                    let previewEnc = try cipher.sealString(preview, aad: ClipCipher.fieldAAD("preview", hash: hash))
                    let sourceEnc = try row.source.map { try cipher.sealString($0, aad: ClipCipher.fieldAAD("source", hash: hash)) }
                    prepared.append(MigratedRow(id: row.id, drop: false, hash: hash, contentEnc: contentEnc, previewEnc: previewEnc, sourceEnc: sourceEnc, newImage: nil, oldFiles: row.imageFile.map { [$0, Self.thumbnailName(for: $0)] } ?? [], newFiles: [], pinned: row.pinned, used: row.used, created: row.created))
                }
            }
        } catch {
            for name in written { try? fm.removeItem(at: directory.appendingPathComponent(name)) }
            throw error
        }

        var obsolete: [String] = []
        var structural = false
        do {
            try exec("BEGIN IMMEDIATE")
            for row in prepared {
                if row.drop {
                    try run("DELETE FROM clips WHERE id = ?", [row.id])
                    obsolete.append(contentsOf: row.oldFiles)
                    structural = true
                } else if let survivor = id(forHash: row.hash), survivor != row.id {
                    try run("UPDATE clips SET pinned = MAX(pinned, ?), used = MAX(used, ?), created = MIN(created, ?) WHERE id = ?", [row.pinned, row.used, row.created, survivor])
                    try run("DELETE FROM clips WHERE id = ?", [row.id])
                    obsolete.append(contentsOf: row.oldFiles)
                    obsolete.append(contentsOf: row.newFiles)
                    structural = true
                } else {
                    try run(
                        "UPDATE clips SET hash = ?, enc = 1, content_enc = ?, preview_enc = ?, source_enc = ?, content = NULL, preview = NULL, source = NULL, image_file = ? WHERE id = ?",
                        [row.hash, row.contentEnc, row.previewEnc, row.sourceEnc, row.newImage, row.id]
                    )
                    obsolete.append(contentsOf: row.oldFiles)
                }
            }
            try migrationFault?(.beforeCommit)
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            for name in written { try? fm.removeItem(at: directory.appendingPathComponent(name)) }
            throw error
        }
        if structural { searchIndex = nil }
        try migrationFault?(.afterCommit)
        for name in obsolete { try? fm.removeItem(at: directory.appendingPathComponent(name)) }
        return plaintextRowCount > 0
    }

    @discardableResult
    func finishEncryptionMigration() -> Bool {
        guard userVersion < Self.schemaVersion else { return true }
        guard plaintextRowCount == 0 else { return false }
        do {
            try exec("VACUUM")
            try exec("PRAGMA wal_checkpoint(TRUNCATE)")
            try exec("PRAGMA user_version = \(Self.schemaVersion)")
            return true
        } catch {
            clipLog.error("Vitrin could not finish the encryption migration: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func count() -> Int {
        Int((try? scalarInt("SELECT COUNT(*) FROM clips")) ?? 0)
    }
}
