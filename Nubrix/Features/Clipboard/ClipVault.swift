import Foundation
import Security

enum ClipVaultOpenResult: Sendable {
    case ready(ClipDatabase, wasReset: Bool)
    case locked(OSStatus)
    case failed(String)
}

struct ClipImageVault: Sendable {
    let directory: URL
    let cipher: ClipCipher

    func write(_ data: Data, named name: String) throws {
        let sealed = try cipher.seal(data, aad: ClipCipher.fileAAD(name))
        let url = directory.appendingPathComponent(name)
        try sealed.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func read(named name: String) -> Data? {
        let url = directory.appendingPathComponent(name)
        switch (name as NSString).pathExtension.lowercased() {
        case "vimg":
            guard let sealed = try? Data(contentsOf: url) else { return nil }
            return try? cipher.open(sealed, aad: ClipCipher.fileAAD(name))
        case "png":
            if let data = try? Data(contentsOf: url, options: .mappedIfSafe) { return data }
            return read(named: (name as NSString).deletingPathExtension + ".vimg")
        default:
            return nil
        }
    }
}

enum ClipVault {
    static func open(directory: URL, keys: VitrinKeyProviding) -> ClipVaultOpenResult {
        var db: ClipDatabase
        do {
            db = try ClipDatabase(directory: directory)
        } catch {
            return .failed(String(describing: error))
        }
        let stored = db.storedKeyID
        let encrypted = db.encryptedRowCount
        let existing = db.count()
        let cipher: ClipCipher
        var wasReset = false

        func wipeAndReopen() -> String? {
            db.close()
            wipeFiles(in: directory)
            do {
                db = try ClipDatabase(directory: directory)
                return nil
            } catch {
                return String(describing: error)
            }
        }

        var failure: ClipVaultOpenResult?

        func bootstrap() -> ClipCipher? {
            if stored != nil || encrypted > 0 {
                if let message = wipeAndReopen() {
                    failure = .failed(message)
                    return nil
                }
                wasReset = existing > 0
            }
            let key = ClipCipher.makeMasterKey()
            let status = keys.create(key)
            if status == errSecSuccess { return ClipCipher(masterKey: key) }
            if status == errSecDuplicateItem, case .ready(let other) = keys.load() {
                return ClipCipher(masterKey: other)
            }
            failure = .locked(status)
            return nil
        }

        switch keys.load() {
        case .locked(let status):
            db.close()
            return .locked(status)
        case .ready(let key):
            let candidate = ClipCipher(masterKey: key)
            if stored == candidate.keyID || (stored == nil && encrypted == 0) {
                cipher = candidate
            } else {
                if let message = wipeAndReopen() { return .failed(message) }
                wasReset = existing > 0
                cipher = candidate
            }
        case .missing:
            guard let created = bootstrap() else {
                db.close()
                return failure ?? .failed("key setup failed")
            }
            cipher = created
        case .invalid:
            _ = keys.delete()
            guard let created = bootstrap() else {
                db.close()
                return failure ?? .failed("key setup failed")
            }
            cipher = created
        }

        do {
            if db.storedKeyID != cipher.keyID { try db.setKeyID(cipher.keyID) }
        } catch {
            db.close()
            return .failed(String(describing: error))
        }
        db.install(cipher)
        return .ready(db, wasReset: wasReset)
    }

    static func reset(directory: URL, keys: VitrinKeyProviding) -> ClipVaultOpenResult {
        wipeFiles(in: directory)
        _ = keys.delete()
        return open(directory: directory, keys: keys)
    }

    static func wipeFiles(in directory: URL) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        let database: Set<String> = ["vitrin.sqlite", "vitrin.sqlite-wal", "vitrin.sqlite-shm"]
        for name in names {
            let ext = (name as NSString).pathExtension.lowercased()
            guard database.contains(name) || ext == "png" || ext == "vimg" else { continue }
            try? fm.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
