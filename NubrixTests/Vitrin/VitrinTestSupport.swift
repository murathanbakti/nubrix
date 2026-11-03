import CryptoKit
import Foundation
import ImageIO
import Security
import SQLite3
import UniformTypeIdentifiers
import XCTest
@testable import Nubrix

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class MemoryKeyStore: VitrinKeyProviding, @unchecked Sendable {
    let label = "memory"

    private let lock = NSLock()
    private var current: VitrinKeyLoad
    private var stored: SymmetricKey?
    private var creates = 0
    private var deletes = 0
    private var loads = 0

    init(_ initial: VitrinKeyLoad = .missing) {
        current = initial
        if case .ready(let key) = initial { stored = key }
    }

    var createCount: Int { locked { creates } }
    var deleteCount: Int { locked { deletes } }
    var loadCount: Int { locked { loads } }
    var storedKey: SymmetricKey? { locked { stored } }

    func configure(_ load: VitrinKeyLoad) {
        locked {
            current = load
            if case .ready(let key) = load { stored = key }
        }
    }

    func load() -> VitrinKeyLoad {
        locked {
            loads += 1
            return current
        }
    }

    func create(_ key: SymmetricKey) -> OSStatus {
        locked {
            creates += 1
            switch current {
            case .missing:
                stored = key
                current = .ready(key)
                return errSecSuccess
            case .ready:
                return errSecDuplicateItem
            case .invalid, .locked:
                return errSecInteractionNotAllowed
            }
        }
    }

    func delete() -> OSStatus {
        locked {
            deletes += 1
            stored = nil
            current = .missing
            return errSecSuccess
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

func keyBytes(_ key: SymmetricKey) -> Data {
    key.withUnsafeBytes { Data($0) }
}

func makePNG(width: Int, height: Int, seed: UInt8 = 0x40) -> Data {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(red: CGFloat(seed) / 255, green: CGFloat(255 - seed) / 255, blue: CGFloat(seed &* 3) / 255, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = context.makeImage()!
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
}

func rawFilesContain(_ marker: Data, in directory: URL) -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return names.sorted().filter { name in
        guard let bytes = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return false }
        return bytes.range(of: marker) != nil
    }
}

func rawFilesContain(_ marker: String, in directory: URL) -> [String] {
    rawFilesContain(Data(marker.utf8), in: directory)
}

func directoryNames(_ directory: URL) -> Set<String> {
    Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
}

func directorySnapshot(_ directory: URL) -> [String: Data] {
    var out: [String: Data] = [:]
    for name in directoryNames(directory) {
        out[name] = try? Data(contentsOf: directory.appendingPathComponent(name))
    }
    return out
}

func sqliteMasterNames(in directory: URL) -> [String] {
    var handle: OpaquePointer?
    let path = directory.appendingPathComponent("vitrin.sqlite").path
    guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        sqlite3_close(handle)
        return []
    }
    defer { sqlite3_close(handle) }
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(handle, "SELECT name FROM sqlite_master", -1, &stmt, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_finalize(stmt) }
    var names: [String] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        if let c = sqlite3_column_text(stmt, 0) { names.append(String(cString: c)) }
    }
    return names
}

class VitrinTestCase: XCTestCase {
    var directory: URL!
    private var openDatabases: [ClipDatabase] = []

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("NubrixTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        openDatabases.forEach { $0.close() }
        openDatabases.removeAll()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    func track(_ db: ClipDatabase) -> ClipDatabase {
        openDatabases.append(db)
        return db
    }

    func openReady(keys: MemoryKeyStore, in dir: URL? = nil, file: StaticString = #filePath, line: UInt = #line) throws -> (db: ClipDatabase, wasReset: Bool) {
        let result = ClipVault.open(directory: dir ?? directory, keys: keys)
        guard case .ready(let db, let wasReset) = result else {
            XCTFail("expected ready, got \(result)", file: file, line: line)
            throw VitrinTestError.notReady
        }
        return (track(db), wasReset)
    }

    @discardableResult
    func addText(_ db: ClipDatabase, _ text: String, kind: ClipKind = .text, source: String? = nil, now: Date = Date(), pinned: Bool = false) throws -> Int64 {
        let hash = try XCTUnwrap(db.textHash(text))
        let id = try db.insert(kind: kind, content: text, imageFile: nil, width: 0, height: 0, hash: hash, source: source, now: now)
        if pinned { db.setPinned(id: id, true) }
        return id
    }

    @discardableResult
    func addImage(_ db: ClipDatabase, png: Data, thumbnail: Data, source: String? = nil, now: Date = Date(), pinned: Bool = false) throws -> (id: Int64, file: String) {
        let hash = try XCTUnwrap(db.imageHash(png))
        let file = try db.writeImage(png: png, thumbnail: thumbnail)
        let id = try db.insert(kind: .image, content: nil, imageFile: file, width: 8, height: 8, hash: hash, source: source, bytes: png.count + thumbnail.count, now: now)
        if pinned { db.setPinned(id: id, true) }
        return (id, file)
    }

    func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
    }
}

enum VitrinTestError: Error {
    case notReady
    case fixture(String)
    case fault
}

final class VitrinV2Fixture {
    struct TextRow {
        let id: Int64
        let kind: ClipKind
        let text: String
        let preview: String
        let textLength: Int
        let source: String?
        let created: Double
        let used: Double
        let pinned: Bool
        let bytes: Int
    }

    struct ImageRow {
        let id: Int64
        let file: String
        let thumbFile: String
        let png: Data
        let thumbnail: Data
        let source: String?
        let width: Int
        let height: Int
        let created: Double
        let used: Double
        let pinned: Bool
        let pngMissing: Bool
    }

    let directory: URL
    private(set) var texts: [TextRow] = []
    private(set) var images: [ImageRow] = []
    private var handle: OpaquePointer?
    private var tick = 0.0

    static let baseStamp = 1_700_000_000.0

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("vitrin.sqlite").path
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw VitrinTestError.fixture("open")
        }
        try exec("PRAGMA journal_mode=WAL")
        try exec("""
        CREATE TABLE clips(
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
            bytes INTEGER NOT NULL DEFAULT 0
        )
        """)
        try exec("CREATE UNIQUE INDEX clips_hash ON clips(hash)")
        try exec("CREATE INDEX clips_used ON clips(used)")
        try exec("CREATE INDEX clips_unpinned_used ON clips(pinned, used DESC, id DESC)")
        try exec("CREATE VIRTUAL TABLE clips_fts USING fts5(content, content='clips', content_rowid='id', tokenize='unicode61 remove_diacritics 2')")
        try exec("CREATE TRIGGER clips_ai AFTER INSERT ON clips BEGIN INSERT INTO clips_fts(rowid, content) VALUES (new.id, COALESCE(new.content, '')); END")
        try exec("CREATE TRIGGER clips_ad AFTER DELETE ON clips BEGIN INSERT INTO clips_fts(clips_fts, rowid, content) VALUES ('delete', old.id, COALESCE(old.content, '')); END")
        try exec("PRAGMA user_version = 2")
    }

    deinit {
        close()
    }

    func close() {
        if let handle {
            sqlite3_close(handle)
        }
        handle = nil
    }

    @discardableResult
    func addText(_ text: String, kind: ClipKind = .text, source: String? = "com.example.app", pinned: Bool = false) throws -> TextRow {
        precondition(kind != .image)
        let scalars = text.unicodeScalars
        let preview = String(String.UnicodeScalarView(scalars.prefix(300)))
        let stamps = nextStamps()
        let hash = Self.sha256Hex(Data(text.utf8))
        let bytes = text.utf8.count
        let id = try insert([
            kind.rawValue, text, preview, scalars.count, nil, 0, 0, hash, source, stamps.created, stamps.used, pinned ? 1 : 0, bytes,
        ])
        let row = TextRow(id: id, kind: kind, text: text, preview: preview, textLength: scalars.count, source: source, created: stamps.created, used: stamps.used, pinned: pinned, bytes: bytes)
        texts.append(row)
        return row
    }

    @discardableResult
    func addImage(seed: UInt8, source: String? = "com.example.shot", pinned: Bool = false, omitPNG: Bool = false) throws -> ImageRow {
        let png = makePNG(width: 16, height: 12, seed: seed)
        let thumbnail = makePNG(width: 8, height: 6, seed: seed)
        let base = UUID().uuidString
        let file = base + ".png"
        let thumbFile = base + ".thumb.png"
        if !omitPNG { try png.write(to: directory.appendingPathComponent(file)) }
        try thumbnail.write(to: directory.appendingPathComponent(thumbFile))
        let stamps = nextStamps()
        let id = try insert([
            ClipKind.image.rawValue, nil, nil, 0, file, 16, 12, Self.sha256Hex(png), source, stamps.created, stamps.used, pinned ? 1 : 0, png.count + thumbnail.count,
        ])
        let row = ImageRow(id: id, file: file, thumbFile: thumbFile, png: png, thumbnail: thumbnail, source: source, width: 16, height: 12, created: stamps.created, used: stamps.used, pinned: pinned, pngMissing: omitPNG)
        images.append(row)
        return row
    }

    func ftsSearch(_ query: String) throws -> [Int64] {
        let tokens = query.split(whereSeparator: { $0.isWhitespace }).map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }
        guard !tokens.isEmpty else { return [] }
        let stmt = try prepare("SELECT clips.id FROM clips JOIN clips_fts ON clips_fts.rowid = clips.id WHERE clips_fts MATCH ? ORDER BY clips.used DESC, clips.id DESC LIMIT 300")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, tokens.joined(separator: " "), -1, sqliteTransientDestructor)
        var ids: [Int64] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            ids.append(sqlite3_column_int64(stmt, 0))
        }
        return ids
    }

    private func nextStamps() -> (created: Double, used: Double) {
        tick += 1
        let created = Self.baseStamp + tick * 100
        return (created, created + 10)
    }

    private func insert(_ values: [Any?]) throws -> Int64 {
        let stmt = try prepare("INSERT INTO clips(kind, content, preview, text_len, image_file, image_w, image_h, hash, source, created, used, pinned, bytes) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)")
        defer { sqlite3_finalize(stmt) }
        for (i, value) in values.enumerated() {
            let idx = Int32(i + 1)
            switch value {
            case nil: sqlite3_bind_null(stmt, idx)
            case let v as String: sqlite3_bind_text(stmt, idx, v, -1, sqliteTransientDestructor)
            case let v as Int: sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Double: sqlite3_bind_double(stmt, idx, v)
            default: throw VitrinTestError.fixture("bind")
            }
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw VitrinTestError.fixture(String(cString: sqlite3_errmsg(handle))) }
        return sqlite3_last_insert_rowid(handle)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw VitrinTestError.fixture(String(cString: sqlite3_errmsg(handle)))
        }
        return stmt
    }

    private func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "exec"
            sqlite3_free(error)
            throw VitrinTestError.fixture(message)
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
