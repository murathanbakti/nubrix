import XCTest
@testable import Nubrix

final class ClipMigrationTests: VitrinTestCase {
    private static let canaryText = "canary-7f3a9c2e-vitrin"
    private static let canarySource = "com.canary.app"

    private struct Seed {
        let fixture: VitrinV2Fixture
        let hello: VitrinV2Fixture.TextRow
        let invitation: VitrinV2Fixture.TextRow
        let canary: VitrinV2Fixture.TextRow
        let pinnedNote: VitrinV2Fixture.TextRow
        let firstImage: VitrinV2Fixture.ImageRow
        let missingImage: VitrinV2Fixture.ImageRow
        let ftsExpectations: [String: [Int64]]
    }

    private static let queries = ["hello", "wor", "çay", "CAY", "link exa", "nubrix 2026", "vit"]

    private func makeSeed() throws -> Seed {
        let fixture = try VitrinV2Fixture(directory: directory)
        let hello = try fixture.addText("hello world", source: "com.apple.Safari", pinned: true)
        try fixture.addText("Çay listesi ve İstanbul notları", source: nil)
        let firstImage = try fixture.addImage(seed: 0x21, source: "com.apple.screencapture")
        try fixture.addText("https://example.com/link/path?q=1", kind: .link, source: "com.google.Chrome")
        try fixture.addText("the world is wide and the wor ld is not", source: "com.apple.Notes")
        try fixture.addImage(seed: 0x52, source: nil, pinned: true)
        let family = "👨‍👩‍👧‍👦"
        let longText = "intro \(family) " + String(repeating: "long line of text ", count: 40) + "tail-marker-zz \(family)"
        XCTAssertGreaterThan(longText.unicodeScalars.count, 300)
        try fixture.addText(longText, source: "com.apple.dt.Xcode")
        try fixture.addText("nubrix 2026 release notes", source: "com.apple.Notes")
        let invitation = try fixture.addText("Please accept the invitation to the meeting", source: "com.apple.mail")
        let missingImage = try fixture.addImage(seed: 0x77, source: "com.apple.screencapture", omitPNG: true)
        let canary = try fixture.addText("note: \(Self.canaryText) end", source: Self.canarySource)
        try fixture.addText("CAY and Cay and çay mixed", source: "com.apple.Notes")
        try fixture.addText("link example https://example.org/x", kind: .link, source: nil)
        let pinnedNote = try fixture.addText("pinned note for the merge", source: "com.apple.Notes", pinned: true)
        try fixture.addText("   \n  whitespace padded\n\n", source: "com.apple.Notes")

        var expectations: [String: [Int64]] = [:]
        for query in Self.queries {
            expectations[query] = try fixture.ftsSearch(query)
        }
        fixture.close()
        return Seed(fixture: fixture, hello: hello, invitation: invitation, canary: canary, pinnedNote: pinnedNote, firstImage: firstImage, missingImage: missingImage, ftsExpectations: expectations)
    }

    private func finishMigration(_ db: ClipDatabase, limit: Int = 2) throws {
        db.runDeferredMigration()
        while try db.migrateEncryptionBatch(limit: limit) {}
        XCTAssertTrue(db.finishEncryptionMigration())
    }

    private func expectedImageFiles(_ seed: Seed, _ db: ClipDatabase) throws -> Set<String> {
        var names = Set<String>()
        for image in seed.fixture.images where !image.pngMissing {
            let file = try XCTUnwrap(db.imageFile(id: image.id))
            names.insert(file)
            names.insert(ClipDatabase.thumbnailName(for: file))
        }
        return names
    }

    private func assertFullyMigrated(_ db: ClipDatabase, _ seed: Seed, file: StaticString = #filePath, line: UInt = #line) throws {
        let fixture = seed.fixture
        XCTAssertEqual(db.plaintextRowCount, 0, file: file, line: line)
        XCTAssertEqual(db.userVersion, 3, file: file, line: line)
        XCTAssertEqual(db.encryptedRowCount, fixture.texts.count + fixture.images.count - 1, file: file, line: line)
        XCTAssertEqual(db.count(), fixture.texts.count + fixture.images.count - 1, file: file, line: line)

        let master = sqliteMasterNames(in: directory)
        XCTAssertTrue(master.contains("clips"), file: file, line: line)
        XCTAssertFalse(master.contains(where: { $0.hasPrefix("clips_fts") || $0 == "clips_ai" || $0 == "clips_ad" }), "\(master)", file: file, line: line)

        let names = directoryNames(directory)
        XCTAssertFalse(names.contains(where: { $0.lowercased().hasSuffix(".png") }), "\(names)", file: file, line: line)
        let vimg = Set(names.filter { $0.hasSuffix(".vimg") })
        XCTAssertEqual(vimg, try expectedImageFiles(seed, db), file: file, line: line)
        XCTAssertEqual(names.subtracting(vimg).subtracting(["vitrin.sqlite", "vitrin.sqlite-wal", "vitrin.sqlite-shm"]), [], file: file, line: line)

        XCTAssertNil(db.summary(id: seed.missingImage.id), file: file, line: line)

        for row in fixture.texts {
            let item = try XCTUnwrap(db.summary(id: row.id), "text \(row.id)", file: file, line: line)
            XCTAssertEqual(item.kind, row.kind, file: file, line: line)
            XCTAssertEqual(item.preview, row.preview, file: file, line: line)
            XCTAssertEqual(item.textLength, row.textLength, file: file, line: line)
            XCTAssertEqual(item.sourceApp, row.source, file: file, line: line)
            XCTAssertEqual(item.pinned, row.pinned, file: file, line: line)
            XCTAssertEqual(item.createdAt.timeIntervalSince1970, row.created, file: file, line: line)
            XCTAssertEqual(item.lastUsedAt.timeIntervalSince1970, row.used, file: file, line: line)
            XCTAssertNil(item.imageFile, file: file, line: line)
            XCTAssertEqual(db.fullText(id: row.id), row.text, file: file, line: line)
            XCTAssertEqual(db.fullText(id: row.id, maxChars: 5), String(String.UnicodeScalarView(row.text.unicodeScalars.prefix(5))), file: file, line: line)
            XCTAssertEqual(db.id(forHash: try XCTUnwrap(db.textHash(row.text))), row.id, file: file, line: line)
        }

        for image in fixture.images where !image.pngMissing {
            let item = try XCTUnwrap(db.summary(id: image.id), "image \(image.id)", file: file, line: line)
            XCTAssertEqual(item.kind, .image, file: file, line: line)
            XCTAssertEqual(item.sourceApp, image.source, file: file, line: line)
            XCTAssertEqual(item.pinned, image.pinned, file: file, line: line)
            XCTAssertEqual(item.imageWidth, image.width, file: file, line: line)
            XCTAssertEqual(item.imageHeight, image.height, file: file, line: line)
            XCTAssertEqual(item.createdAt.timeIntervalSince1970, image.created, file: file, line: line)
            XCTAssertEqual(item.lastUsedAt.timeIntervalSince1970, image.used, file: file, line: line)
            let name = try XCTUnwrap(item.imageFile, file: file, line: line)
            XCTAssertTrue(name.hasSuffix(".vimg"), file: file, line: line)
            XCTAssertEqual(db.imageData(named: name), image.png, file: file, line: line)
            XCTAssertEqual(db.imageData(named: ClipDatabase.thumbnailName(for: name)), image.thumbnail, file: file, line: line)
            XCTAssertEqual(db.id(forHash: try XCTUnwrap(db.imageHash(image.png))), image.id, file: file, line: line)
        }

        XCTAssertEqual(rawFilesContain(Self.canaryText, in: directory), [], file: file, line: line)
        XCTAssertEqual(rawFilesContain(Self.canarySource, in: directory), [], file: file, line: line)
        XCTAssertEqual(rawFilesContain("tail-marker-zz", in: directory), [], file: file, line: line)
        XCTAssertEqual(rawFilesContain("whitespace padded", in: directory), [], file: file, line: line)
        XCTAssertEqual(rawFilesContain("com.apple.Safari", in: directory), [], file: file, line: line)

        XCTAssertEqual(db.search("vitrin", limit: 10).map(\.id), [seed.canary.id], file: file, line: line)
        XCTAssertEqual(db.search("tail-marker", limit: 10).count, 1, file: file, line: line)
    }

    func testFixtureContainsPlaintextBeforeMigration() throws {
        let seed = try makeSeed()
        XCTAssertTrue(rawFilesContain(Self.canaryText, in: directory).contains("vitrin.sqlite"))
        XCTAssertEqual(seed.fixture.images.count, 3)
        XCTAssertTrue(sqliteMasterNames(in: directory).contains("clips_fts"))
        for query in Self.queries {
            XCTAssertFalse(try XCTUnwrap(seed.ftsExpectations[query]).isEmpty, query)
        }
    }

    func testOpenDoesNotWipeV2DataAndMigrationCompletes() throws {
        let seed = try makeSeed()
        let keys = MemoryKeyStore(.missing)
        let (db, wasReset) = try openReady(keys: keys)
        XCTAssertFalse(wasReset)
        XCTAssertEqual(db.count(), seed.fixture.texts.count + seed.fixture.images.count)
        XCTAssertEqual(db.plaintextRowCount, db.count())
        XCTAssertEqual(db.userVersion, 2)
        XCTAssertEqual(keys.createCount, 1)
        XCTAssertEqual(keys.deleteCount, 0)

        try finishMigration(db)
        try assertFullyMigrated(db, seed)
        XCTAssertEqual(db.sweepOrphans(), 0)
    }

    func testMigrationWithLargeBatchMatchesSmallBatch() throws {
        let seed = try makeSeed()
        let (db, _) = try openReady(keys: MemoryKeyStore(.missing))
        try finishMigration(db, limit: 200)
        try assertFullyMigrated(db, seed)
    }

    func testMigrationIsIdempotentAfterCompletion() throws {
        let seed = try makeSeed()
        let keys = MemoryKeyStore(.missing)
        let (db, _) = try openReady(keys: keys)
        try finishMigration(db)
        XCTAssertFalse(try db.migrateEncryptionBatch(limit: 2))
        XCTAssertTrue(db.finishEncryptionMigration())
        db.runDeferredMigration()
        db.close()
        let (again, wasReset) = try openReady(keys: keys)
        XCTAssertFalse(wasReset)
        again.runDeferredMigration()
        try assertFullyMigrated(again, seed)
    }

    func testFinishRefusesWhilePlaintextRowsRemain() throws {
        _ = try makeSeed()
        let (db, _) = try openReady(keys: MemoryKeyStore(.missing))
        db.runDeferredMigration()
        XCTAssertTrue(try db.migrateEncryptionBatch(limit: 2))
        XCTAssertFalse(db.finishEncryptionMigration())
        XCTAssertEqual(db.userVersion, 2)
    }

    func testCrashBeforeCommitThenReopenFinishesIdentically() throws {
        let seed = try makeSeed()
        let keys = MemoryKeyStore(.missing)
        let (db, _) = try openReady(keys: keys)
        var batches = 0
        db.migrationFault = { point in
            guard point == .beforeCommit else { return }
            batches += 1
            if batches == 2 { throw VitrinTestError.fault }
        }
        db.runDeferredMigration()
        XCTAssertTrue(try db.migrateEncryptionBatch(limit: 2))
        XCTAssertThrowsError(try db.migrateEncryptionBatch(limit: 2))
        XCTAssertEqual(db.plaintextRowCount, seed.fixture.texts.count + seed.fixture.images.count - 2)
        XCTAssertTrue(exists(seed.firstImage.file))
        XCTAssertTrue(exists(seed.firstImage.thumbFile))
        XCTAssertFalse(directoryNames(directory).contains(where: { $0.hasSuffix(".vimg") }))
        db.close()

        let (reopened, wasReset) = try openReady(keys: keys)
        XCTAssertFalse(wasReset)
        XCTAssertEqual(reopened.encryptedRowCount, 2)
        try finishMigration(reopened)
        try assertFullyMigrated(reopened, seed)
        XCTAssertEqual(keys.createCount, 1)
    }

    func testCrashAfterCommitLeavesOldPNGsThatReopenSweeps() throws {
        let seed = try makeSeed()
        let keys = MemoryKeyStore(.missing)
        let (db, _) = try openReady(keys: keys)
        var batches = 0
        db.migrationFault = { point in
            guard point == .afterCommit else { return }
            batches += 1
            if batches == 2 { throw VitrinTestError.fault }
        }
        db.runDeferredMigration()
        XCTAssertTrue(try db.migrateEncryptionBatch(limit: 2))
        XCTAssertThrowsError(try db.migrateEncryptionBatch(limit: 2))
        XCTAssertEqual(db.encryptedRowCount, 4)
        XCTAssertTrue(exists(seed.firstImage.file), "old PNG should survive the simulated crash")
        XCTAssertTrue(exists(seed.firstImage.thumbFile))
        XCTAssertEqual(db.summary(id: seed.firstImage.id)?.imageFile?.hasSuffix(".vimg"), true)
        db.close()

        let (reopened, _) = try openReady(keys: keys)
        reopened.runDeferredMigration()
        XCTAssertFalse(exists(seed.firstImage.file))
        XCTAssertFalse(exists(seed.firstImage.thumbFile))
        XCTAssertEqual(reopened.encryptedRowCount, 4)
        while try reopened.migrateEncryptionBatch(limit: 2) {}
        XCTAssertTrue(reopened.finishEncryptionMigration())
        try assertFullyMigrated(reopened, seed)
    }

    func testCrashOnFirstBatchAndEveryBatchStillConverges() throws {
        let seed = try makeSeed()
        let keys = MemoryKeyStore(.missing)
        var current = try openReady(keys: keys).db
        var attempts = 0
        var finished = false
        while !finished && attempts < 40 {
            attempts += 1
            let point: ClipMigrationFaultPoint = attempts.isMultiple(of: 2) ? .afterCommit : .beforeCommit
            var seen = 0
            current.migrationFault = { p in
                guard p == point else { return }
                seen += 1
                if seen == 2 { throw VitrinTestError.fault }
            }
            current.runDeferredMigration()
            do {
                while try current.migrateEncryptionBatch(limit: 2) {}
                finished = true
            } catch {
                current.close()
                current = try openReady(keys: keys).db
            }
        }
        XCTAssertTrue(finished)
        XCTAssertGreaterThan(attempts, 1)
        current.migrationFault = nil
        current.runDeferredMigration()
        XCTAssertTrue(current.finishEncryptionMigration())
        try assertFullyMigrated(current, seed)
    }

    func testMergeWithRecapturedDuplicateKeepsOneRowPinnedAndNewestUsed() throws {
        let seed = try makeSeed()
        let keys = MemoryKeyStore(.missing)
        let (db, _) = try openReady(keys: keys)
        let text = seed.pinnedNote.text
        let newer = Date(timeIntervalSince1970: seed.pinnedNote.used + 5000)
        let duplicate = try addText(db, text, source: "com.apple.Notes", now: newer)
        XCTAssertNotEqual(duplicate, seed.pinnedNote.id)
        XCTAssertEqual(db.plaintextRowCount, seed.fixture.texts.count + seed.fixture.images.count)

        try finishMigration(db)

        XCTAssertNil(db.summary(id: seed.pinnedNote.id))
        let survivor = try XCTUnwrap(db.summary(id: duplicate))
        XCTAssertTrue(survivor.pinned)
        XCTAssertEqual(survivor.lastUsedAt.timeIntervalSince1970, newer.timeIntervalSince1970)
        XCTAssertEqual(survivor.createdAt.timeIntervalSince1970, seed.pinnedNote.created)
        XCTAssertEqual(db.id(forHash: try XCTUnwrap(db.textHash(text))), duplicate)
        XCTAssertEqual(db.search("pinned note for the merge", limit: 10).map(\.id), [duplicate])
        XCTAssertEqual(db.count(), seed.fixture.texts.count + seed.fixture.images.count - 1)
        XCTAssertEqual(db.plaintextRowCount, 0)
        XCTAssertEqual(db.userVersion, 3)
    }

    func testMergeKeepsOlderSurvivorUsedWhenFixtureRowIsNewer() throws {
        let seed = try makeSeed()
        let (db, _) = try openReady(keys: MemoryKeyStore(.missing))
        let older = Date(timeIntervalSince1970: 1000)
        let duplicate = try addText(db, seed.hello.text, source: "com.apple.Safari", now: older)
        try finishMigration(db)
        XCTAssertNil(db.summary(id: seed.hello.id))
        let survivor = try XCTUnwrap(db.summary(id: duplicate))
        XCTAssertTrue(survivor.pinned)
        XCTAssertEqual(survivor.lastUsedAt.timeIntervalSince1970, seed.hello.used)
        XCTAssertEqual(survivor.createdAt.timeIntervalSince1970, 1000)
        XCTAssertEqual(db.search("hello", limit: 10).filter { $0.id == duplicate }.count, 1)
    }

    func testSearchParityIsASupersetOfOldFTS() throws {
        let seed = try makeSeed()
        let (db, _) = try openReady(keys: MemoryKeyStore(.missing))
        try finishMigration(db)

        for query in Self.queries {
            let old = try XCTUnwrap(seed.ftsExpectations[query])
            let new = db.search(query, limit: 300).map(\.id)
            XCTAssertTrue(Set(old).isSubset(of: Set(new)), "\(query): old \(old) new \(new)")
            let items = db.search(query, limit: 300)
            XCTAssertEqual(items.map(\.lastUsedAt), items.map(\.lastUsedAt).sorted(by: >), query)
        }
    }

    func testSubstringSearchIsTheDocumentedBehaviorChange() throws {
        let seed = try makeSeed()
        let (db, _) = try openReady(keys: MemoryKeyStore(.missing))
        try finishMigration(db)

        let old = try XCTUnwrap(seed.ftsExpectations["vit"])
        let new = db.search("vit", limit: 300).map(\.id)
        XCTAssertFalse(old.contains(seed.invitation.id))
        XCTAssertTrue(new.contains(seed.invitation.id))
        XCTAssertTrue(old.contains(seed.canary.id))
        XCTAssertTrue(new.contains(seed.canary.id))
        XCTAssertEqual(Set(new).subtracting(old), [seed.invitation.id])
    }

    func testSearchWorksBeforeMigrationCompletesOnMixedRows() throws {
        let seed = try makeSeed()
        let (db, _) = try openReady(keys: MemoryKeyStore(.missing))
        db.runDeferredMigration()
        XCTAssertTrue(try db.migrateEncryptionBatch(limit: 2))
        XCTAssertGreaterThan(db.encryptedRowCount, 0)
        XCTAssertGreaterThan(db.plaintextRowCount, 0)
        for query in ["hello", "vit", "wor"] {
            let old = try XCTUnwrap(seed.ftsExpectations[query])
            XCTAssertTrue(Set(old).isSubset(of: Set(db.search(query, limit: 300).map(\.id))), query)
        }
        let newcomer = try addText(db, "captured during migration")
        XCTAssertEqual(db.search("during migration", limit: 5).map(\.id), [newcomer])
        while try db.migrateEncryptionBatch(limit: 2) {}
        XCTAssertEqual(db.search("during migration", limit: 5).map(\.id), [newcomer])
        XCTAssertEqual(db.search("hello", limit: 5).map(\.id), [seed.hello.id])
    }
}
