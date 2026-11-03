import CryptoKit
import Security
import XCTest
@testable import Nubrix

final class ClipVaultTests: VitrinTestCase {
    private func seedEncryptedHistory(keys: MemoryKeyStore) throws -> (keyID: String, imageFile: String) {
        let (db, _) = try openReady(keys: keys)
        try addText(db, "encrypted history row", source: "com.test.app")
        let image = try addImage(db, png: makePNG(width: 8, height: 8), thumbnail: makePNG(width: 4, height: 4))
        let keyID = try XCTUnwrap(db.storedKeyID)
        db.close()
        return (keyID, image.file)
    }

    func testFreshDirectoryCreatesKeyAndIsReady() throws {
        let keys = MemoryKeyStore(.missing)
        let (db, wasReset) = try openReady(keys: keys)
        XCTAssertFalse(wasReset)
        XCTAssertEqual(keys.createCount, 1)
        XCTAssertEqual(keys.deleteCount, 0)
        let key = try XCTUnwrap(keys.storedKey)
        XCTAssertEqual(db.storedKeyID, ClipCipher(masterKey: key).keyID)
        XCTAssertNotNil(db.cipher)
        XCTAssertNotNil(db.imageVault)
        XCTAssertEqual(db.count(), 0)
        XCTAssertEqual(db.userVersion, ClipDatabase.schemaVersion)
    }

    func testReopenWithSameKeyKeepsDataAndKeyID() throws {
        let keys = MemoryKeyStore(.missing)
        let seeded = try seedEncryptedHistory(keys: keys)
        let key = try XCTUnwrap(keys.storedKey)

        let again = MemoryKeyStore(.ready(SymmetricKey(data: keyBytes(key))))
        let (db, wasReset) = try openReady(keys: again)
        XCTAssertFalse(wasReset)
        XCTAssertEqual(db.storedKeyID, seeded.keyID)
        XCTAssertEqual(db.count(), 2)
        XCTAssertEqual(db.encryptedRowCount, 2)
        XCTAssertEqual(db.search("encrypted history", limit: 5).count, 1)
        XCTAssertNotNil(db.imageData(named: seeded.imageFile))
        XCTAssertEqual(again.createCount, 0)
        XCTAssertEqual(again.deleteCount, 0)
        XCTAssertTrue(exists(seeded.imageFile))
    }

    func testLockedWithEncryptedRowsTouchesNothing() throws {
        for status in [errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled] {
            let dir = directory.appendingPathComponent("case-\(status)", isDirectory: true)
            let keys = MemoryKeyStore(.missing)
            let (db, _) = try openReady(keys: keys, in: dir)
            try addText(db, "locked row", source: "com.test.app")
            try addImage(db, png: makePNG(width: 8, height: 8), thumbnail: makePNG(width: 4, height: 4))
            db.close()

            let before = directorySnapshot(dir)
            XCTAssertFalse(before.isEmpty)
            let locked = MemoryKeyStore(.locked(status))
            let result = ClipVault.open(directory: dir, keys: locked)
            guard case .locked(let reported) = result else {
                XCTFail("expected locked for \(status), got \(result)")
                continue
            }
            XCTAssertEqual(reported, status)
            let after = directorySnapshot(dir)
            XCTAssertEqual(Set(after.keys), Set(before.keys), "status \(status)")
            XCTAssertEqual(before.keys.filter { $0 != "vitrin.sqlite-shm" && after[$0] != before[$0] }.sorted(), [], "status \(status)")
            XCTAssertEqual(locked.createCount, 0)
            XCTAssertEqual(locked.deleteCount, 0)
            XCTAssertEqual(locked.loadCount, 1)
        }
    }

    func testLockedThenUnlockedKeepsHistory() throws {
        let keys = MemoryKeyStore(.missing)
        _ = try seedEncryptedHistory(keys: keys)
        keys.configure(.locked(errSecAuthFailed))
        guard case .locked = ClipVault.open(directory: directory, keys: keys) else {
            return XCTFail("expected locked")
        }
        keys.configure(.ready(try XCTUnwrap(keys.storedKey)))
        let (db, wasReset) = try openReady(keys: keys)
        XCTAssertFalse(wasReset)
        XCTAssertEqual(db.count(), 2)
        XCTAssertEqual(keys.createCount, 1)
        XCTAssertEqual(keys.deleteCount, 0)
    }

    func testLockedOnFreshDirectoryReportsLocked() throws {
        let keys = MemoryKeyStore(.locked(errSecAuthFailed))
        guard case .locked(let status) = ClipVault.open(directory: directory, keys: keys) else {
            return XCTFail("expected locked")
        }
        XCTAssertEqual(status, errSecAuthFailed)
        XCTAssertEqual(keys.createCount, 0)
        XCTAssertEqual(keys.deleteCount, 0)
    }

    func testMissingKeyWithEncryptedRowsWipesAndStartsOver() throws {
        let first = MemoryKeyStore(.missing)
        let seeded = try seedEncryptedHistory(keys: first)
        XCTAssertTrue(exists(seeded.imageFile))

        let second = MemoryKeyStore(.missing)
        let (db, wasReset) = try openReady(keys: second)
        XCTAssertTrue(wasReset)
        XCTAssertEqual(db.count(), 0)
        XCTAssertEqual(second.createCount, 1)
        XCTAssertEqual(second.deleteCount, 0)
        XCTAssertNotEqual(db.storedKeyID, seeded.keyID)
        XCTAssertEqual(db.storedKeyID, ClipCipher(masterKey: try XCTUnwrap(second.storedKey)).keyID)
        XCTAssertFalse(exists(seeded.imageFile))
        XCTAssertFalse(directoryNames(directory).contains(where: { $0.hasSuffix(".vimg") }))
        XCTAssertEqual(rawFilesContain("encrypted history row", in: directory), [])
        XCTAssertNotNil(db.cipher)
    }

    func testMismatchedKeyWipesAndStartsOver() throws {
        let first = MemoryKeyStore(.missing)
        let seeded = try seedEncryptedHistory(keys: first)
        let otherKey = ClipCipher.makeMasterKey()

        let second = MemoryKeyStore(.ready(otherKey))
        let (db, wasReset) = try openReady(keys: second)
        XCTAssertTrue(wasReset)
        XCTAssertEqual(db.count(), 0)
        XCTAssertEqual(db.storedKeyID, ClipCipher(masterKey: otherKey).keyID)
        XCTAssertNotEqual(db.storedKeyID, seeded.keyID)
        XCTAssertEqual(second.createCount, 0)
        XCTAssertEqual(second.deleteCount, 0)
        XCTAssertFalse(exists(seeded.imageFile))
        XCTAssertEqual(directoryNames(directory).filter { $0.hasSuffix(".vimg") }, [])

        _ = try addText(db, "new history")
        XCTAssertEqual(db.count(), 1)
    }

    func testMismatchedKeyOnEmptyKeyedDatabaseIsNotReportedAsReset() throws {
        let first = MemoryKeyStore(.missing)
        let (db, _) = try openReady(keys: first)
        db.close()
        let (reopened, wasReset) = try openReady(keys: MemoryKeyStore(.ready(ClipCipher.makeMasterKey())))
        XCTAssertFalse(wasReset)
        XCTAssertEqual(reopened.count(), 0)
    }

    func testInvalidKeyDeletesItemAndWipesExistingData() throws {
        let first = MemoryKeyStore(.missing)
        let seeded = try seedEncryptedHistory(keys: first)

        let second = MemoryKeyStore(.invalid)
        let (db, wasReset) = try openReady(keys: second)
        XCTAssertTrue(wasReset)
        XCTAssertEqual(second.deleteCount, 1)
        XCTAssertEqual(second.createCount, 1)
        XCTAssertEqual(db.count(), 0)
        XCTAssertNotEqual(db.storedKeyID, seeded.keyID)
        XCTAssertFalse(exists(seeded.imageFile))
        XCTAssertNotNil(second.storedKey)
    }

    func testInvalidKeyOnFreshDirectoryCreatesNewKeyWithoutReset() throws {
        let keys = MemoryKeyStore(.invalid)
        let (db, wasReset) = try openReady(keys: keys)
        XCTAssertFalse(wasReset)
        XCTAssertEqual(keys.deleteCount, 1)
        XCTAssertEqual(keys.createCount, 1)
        XCTAssertNotNil(db.cipher)
    }

    func testResetFromLockedStateYieldsEmptyDatabaseAndNewKey() throws {
        let first = MemoryKeyStore(.missing)
        let seeded = try seedEncryptedHistory(keys: first)
        let locked = MemoryKeyStore(.locked(errSecAuthFailed))
        guard case .locked = ClipVault.open(directory: directory, keys: locked) else {
            return XCTFail("expected locked")
        }
        XCTAssertEqual(locked.deleteCount, 0)

        let result = ClipVault.reset(directory: directory, keys: locked)
        guard case .ready(let raw, let wasReset) = result else {
            return XCTFail("expected ready after reset, got \(result)")
        }
        let db = track(raw)
        XCTAssertFalse(wasReset)
        XCTAssertEqual(locked.deleteCount, 1)
        XCTAssertEqual(locked.createCount, 1)
        XCTAssertEqual(db.count(), 0)
        XCTAssertNotEqual(db.storedKeyID, seeded.keyID)
        XCTAssertFalse(exists(seeded.imageFile))
        XCTAssertEqual(rawFilesContain("encrypted history row", in: directory), [])
        XCTAssertNotNil(db.cipher)
    }

    func testResetFromReadyStateReplacesKey() throws {
        let keys = MemoryKeyStore(.missing)
        let seeded = try seedEncryptedHistory(keys: keys)
        let result = ClipVault.reset(directory: directory, keys: keys)
        guard case .ready(let raw, _) = result else { return XCTFail("expected ready") }
        let db = track(raw)
        XCTAssertEqual(db.count(), 0)
        XCTAssertNotEqual(db.storedKeyID, seeded.keyID)
        XCTAssertEqual(keys.deleteCount, 1)
        XCTAssertEqual(keys.createCount, 2)
    }

    func testV2DatabaseWithMissingKeyKeepsRowsAndCreatesKey() throws {
        let fixture = try VitrinV2Fixture(directory: directory)
        try fixture.addText("legacy text", source: "com.legacy.app")
        try fixture.addText("https://legacy.example", kind: .link)
        let image = try fixture.addImage(seed: 0x44)
        fixture.close()

        let keys = MemoryKeyStore(.missing)
        let (db, wasReset) = try openReady(keys: keys)
        XCTAssertFalse(wasReset)
        XCTAssertEqual(db.count(), 3)
        XCTAssertEqual(db.plaintextRowCount, 3)
        XCTAssertEqual(db.encryptedRowCount, 0)
        XCTAssertEqual(keys.createCount, 1)
        XCTAssertEqual(keys.deleteCount, 0)
        XCTAssertNotNil(db.storedKeyID)
        XCTAssertTrue(exists(image.file))
        XCTAssertTrue(exists(image.thumbFile))
        XCTAssertEqual(db.fullText(id: 1), "legacy text")
        XCTAssertEqual(db.summary(id: 1)?.sourceApp, "com.legacy.app")
        XCTAssertEqual(db.userVersion, 2)
    }

    func testV2DatabaseWithExistingKeyIsKept() throws {
        let fixture = try VitrinV2Fixture(directory: directory)
        try fixture.addText("legacy text")
        fixture.close()
        let key = ClipCipher.makeMasterKey()
        let keys = MemoryKeyStore(.ready(key))
        let (db, wasReset) = try openReady(keys: keys)
        XCTAssertFalse(wasReset)
        XCTAssertEqual(db.count(), 1)
        XCTAssertEqual(db.storedKeyID, ClipCipher(masterKey: key).keyID)
        XCTAssertEqual(keys.createCount, 0)
    }

    func testPartiallyMigratedDatabaseWithWrongKeyIsWiped() throws {
        let fixture = try VitrinV2Fixture(directory: directory)
        try fixture.addText("one")
        try fixture.addText("two")
        fixture.close()
        let first = MemoryKeyStore(.missing)
        let (db, _) = try openReady(keys: first)
        db.runDeferredMigration()
        XCTAssertTrue(try db.migrateEncryptionBatch(limit: 1))
        XCTAssertEqual(db.encryptedRowCount, 1)
        db.close()

        let (fresh, wasReset) = try openReady(keys: MemoryKeyStore(.ready(ClipCipher.makeMasterKey())))
        XCTAssertTrue(wasReset)
        XCTAssertEqual(fresh.count(), 0)
    }

    func testWipeFilesRemovesOnlyDatabaseAndImageFiles() throws {
        let names = ["vitrin.sqlite", "vitrin.sqlite-wal", "vitrin.sqlite-shm", "a.png", "b.thumb.png", "c.vimg", "c.thumb.vimg", "key", "notes.txt", "other.sqlite"]
        for name in names {
            try Data("x".utf8).write(to: directory.appendingPathComponent(name))
        }
        ClipVault.wipeFiles(in: directory)
        XCTAssertEqual(directoryNames(directory), ["key", "notes.txt", "other.sqlite"])
        ClipVault.wipeFiles(in: directory.appendingPathComponent("does-not-exist"))
    }

    func testImageVaultRoundTripAndPlainPNGFallback() throws {
        let keys = MemoryKeyStore(.missing)
        let (db, _) = try openReady(keys: keys)
        let vault = try XCTUnwrap(db.imageVault)
        let data = makePNG(width: 8, height: 8)
        try vault.write(data, named: "x.vimg")
        XCTAssertEqual(vault.read(named: "x.vimg"), data)
        XCTAssertNil(vault.read(named: "nope.vimg"))
        XCTAssertNil(vault.read(named: "x.txt"))
        let raw = try Data(contentsOf: directory.appendingPathComponent("x.vimg"))
        XCTAssertNil(raw.range(of: data))
        let attrs = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("x.vimg").path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        try data.write(to: directory.appendingPathComponent("legacy.png"))
        XCTAssertEqual(vault.read(named: "legacy.png"), data)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("legacy.png"))
        try vault.write(data, named: "legacy.vimg")
        XCTAssertEqual(vault.read(named: "legacy.png"), data)
    }

    #if DEBUG
    func testFileKeyStoreRoundTrip() throws {
        let url = directory.appendingPathComponent("keys", isDirectory: true).appendingPathComponent("key")
        let store = FileVitrinKeyStore(url: url)
        guard case .missing = store.load() else { return XCTFail("expected missing") }

        let key = ClipCipher.makeMasterKey()
        XCTAssertEqual(store.create(key), errSecSuccess)
        guard case .ready(let loaded) = store.load() else { return XCTFail("expected ready") }
        XCTAssertEqual(keyBytes(loaded), keyBytes(key))

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try Data(contentsOf: url).count, 32)

        XCTAssertEqual(store.create(ClipCipher.makeMasterKey()), errSecDuplicateItem)
        guard case .ready(let still) = store.load() else { return XCTFail("expected ready") }
        XCTAssertEqual(keyBytes(still), keyBytes(key))

        XCTAssertEqual(store.delete(), errSecSuccess)
        guard case .missing = store.load() else { return XCTFail("expected missing after delete") }
        XCTAssertEqual(store.delete(), errSecSuccess)
    }

    func testFileKeyStoreRejectsWrongLength() throws {
        let url = directory.appendingPathComponent("key")
        try Data(repeating: 1, count: 31).write(to: url)
        let store = FileVitrinKeyStore(url: url)
        guard case .invalid = store.load() else { return XCTFail("expected invalid") }
        try Data().write(to: url)
        guard case .invalid = store.load() else { return XCTFail("expected invalid for empty file") }
    }

    func testDebugDefaultKeyStoreIsFileBackedInsideDirectory() throws {
        let store = VitrinKeyStores.makeDefault(directory: directory)
        XCTAssertTrue(store is FileVitrinKeyStore)
        XCTAssertEqual(store.label, "Debug key file")
        guard case .missing = store.load() else { return XCTFail("expected missing") }
        XCTAssertEqual(store.create(ClipCipher.makeMasterKey()), errSecSuccess)
        XCTAssertTrue(exists("key"))
        XCTAssertEqual(store.delete(), errSecSuccess)
        XCTAssertFalse(exists("key"))
    }

    func testVaultWithFileKeyStoreKeepsKeyFileAcrossOpensAndWipes() throws {
        let store = FileVitrinKeyStore(url: directory.appendingPathComponent("key"))
        guard case .ready(let db, _) = ClipVault.open(directory: directory, keys: store) else { return XCTFail("expected ready") }
        _ = track(db)
        _ = try addText(db, "file key row")
        let keyID = db.storedKeyID
        db.close()
        XCTAssertTrue(exists("key"))

        guard case .ready(let again, let wasReset) = ClipVault.open(directory: directory, keys: store) else { return XCTFail("expected ready") }
        _ = track(again)
        XCTAssertFalse(wasReset)
        XCTAssertEqual(again.storedKeyID, keyID)
        XCTAssertEqual(again.count(), 1)
        again.close()

        guard case .ready(let reset, _) = ClipVault.reset(directory: directory, keys: store) else { return XCTFail("expected ready") }
        _ = track(reset)
        XCTAssertEqual(reset.count(), 0)
        XCTAssertNotEqual(reset.storedKeyID, keyID)
        XCTAssertTrue(exists("key"))
    }
    #endif
}
