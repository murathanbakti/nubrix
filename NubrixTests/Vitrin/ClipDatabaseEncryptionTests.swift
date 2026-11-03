import CoreGraphics
import XCTest
@testable import Nubrix

final class ClipDatabaseEncryptionTests: VitrinTestCase {
    private var keys: MemoryKeyStore!
    private var db: ClipDatabase!

    override func setUpWithError() throws {
        try super.setUpWithError()
        keys = MemoryKeyStore(.missing)
        db = try openReady(keys: keys).db
    }

    func testTextRoundTrip() throws {
        let id = try addText(db, "hello encrypted world", source: "com.apple.Safari")
        let item = try XCTUnwrap(db.summary(id: id))
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.preview, "hello encrypted world")
        XCTAssertEqual(item.textLength, 21)
        XCTAssertEqual(item.sourceApp, "com.apple.Safari")
        XCTAssertFalse(item.pinned)
        XCTAssertNil(item.imageFile)
        XCTAssertEqual(db.fullText(id: id), "hello encrypted world")
        XCTAssertEqual(db.summaries().map(\.id), [id])
        XCTAssertEqual(db.encryptedRowCount, 1)
        XCTAssertEqual(db.plaintextRowCount, 0)
    }

    func testLinkRoundTripAndNilSource() throws {
        let id = try addText(db, "https://example.com/a?b=c", kind: .link)
        let item = try XCTUnwrap(db.summary(id: id))
        XCTAssertEqual(item.kind, .link)
        XCTAssertEqual(item.preview, "https://example.com/a?b=c")
        XCTAssertNil(item.sourceApp)
        XCTAssertEqual(db.fullText(id: id), "https://example.com/a?b=c")
    }

    func testSummariesOrderedByUsedDescending() throws {
        let old = try addText(db, "old", now: Date(timeIntervalSince1970: 1000))
        let new = try addText(db, "new", now: Date(timeIntervalSince1970: 3000))
        let mid = try addText(db, "mid", now: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(db.summaries().map(\.id), [new, mid, old])
        XCTAssertEqual(db.summaries(limit: 2).map(\.id), [new, mid])
        XCTAssertTrue(db.touch(id: old, now: Date(timeIntervalSince1970: 5000)))
        XCTAssertEqual(db.summaries().map(\.id), [old, new, mid])
    }

    func testLongTextPreviewAndFullText() throws {
        let text = String(repeating: "0123456789", count: 60) + "END"
        let id = try addText(db, text)
        let item = try XCTUnwrap(db.summary(id: id))
        XCTAssertEqual(item.preview?.unicodeScalars.count, ClipDatabase.previewLength)
        XCTAssertEqual(item.textLength, 603)
        XCTAssertFalse(item.isTextComplete)
        XCTAssertEqual(db.fullText(id: id), text)
        XCTAssertEqual(db.fullText(id: id, maxChars: 10), "0123456789")
        XCTAssertEqual(db.fullText(id: id, maxChars: 0), "")
        XCTAssertEqual(db.fullText(id: id, maxChars: 10_000), text)
        XCTAssertNil(db.fullText(id: 12345))
    }

    func testFullTextMaxCharsCountsUnicodeScalars() throws {
        let family = "👨‍👩‍👧‍👦"
        XCTAssertEqual(family.unicodeScalars.count, 7)
        let text = "a" + family + "b" + family + "c"
        let id = try addText(db, text)
        XCTAssertEqual(db.fullText(id: id, maxChars: 1), "a")
        let three = try XCTUnwrap(db.fullText(id: id, maxChars: 3))
        XCTAssertEqual(three.unicodeScalars.count, 3)
        XCTAssertEqual(String(String.UnicodeScalarView(text.unicodeScalars.prefix(3))), three)
        XCTAssertEqual(db.fullText(id: id, maxChars: 8), "a" + family)
        XCTAssertEqual(db.fullText(id: id), text)
        XCTAssertEqual(try XCTUnwrap(db.summary(id: id)).textLength, text.unicodeScalars.count)
    }

    func testEmojiPreviewIsCutOnScalarBoundary() throws {
        let text = String(repeating: "👨‍👩‍👧‍👦", count: 100)
        let id = try addText(db, text)
        let preview = try XCTUnwrap(db.summary(id: id)?.preview)
        XCTAssertEqual(preview.unicodeScalars.count, 300)
        XCTAssertEqual(try XCTUnwrap(db.summary(id: id)).textLength, 700)
    }

    func testImageRoundTripAndDecode() throws {
        let png = makePNG(width: 64, height: 48, seed: 0x10)
        let thumbnail = makePNG(width: 16, height: 12, seed: 0x10)
        let (id, file) = try addImage(db, png: png, thumbnail: thumbnail, source: "dev.nubrix.screenshot")
        XCTAssertTrue(file.hasSuffix(".vimg"))
        let thumbName = ClipDatabase.thumbnailName(for: file)
        XCTAssertTrue(thumbName.hasSuffix(".thumb.vimg"))
        XCTAssertTrue(exists(file))
        XCTAssertTrue(exists(thumbName))
        XCTAssertFalse(directoryNames(directory).contains(where: { $0.hasSuffix(".png") }))

        let item = try XCTUnwrap(db.summary(id: id))
        XCTAssertEqual(item.kind, .image)
        XCTAssertEqual(item.imageFile, file)
        XCTAssertEqual(item.thumbnailFile, thumbName)
        XCTAssertEqual(item.sourceApp, "dev.nubrix.screenshot")
        XCTAssertNil(item.preview)
        XCTAssertEqual(db.imageFile(id: id), file)

        XCTAssertEqual(db.imageData(named: file), png)
        XCTAssertEqual(db.imageData(named: thumbName), thumbnail)
        let main = try XCTUnwrap(ClipImageLoader.downsample(data: try XCTUnwrap(db.imageData(named: file)), maxPixel: 32))
        XCTAssertEqual(max(main.width, main.height), 32)
        let thumb = try XCTUnwrap(ClipImageLoader.downsample(data: try XCTUnwrap(db.imageData(named: thumbName)), maxPixel: 100))
        XCTAssertEqual(thumb.width, 16)
        XCTAssertEqual(thumb.height, 12)
    }

    func testEncryptedImageFileIsNotAPNG() throws {
        let png = makePNG(width: 8, height: 8)
        let (_, file) = try addImage(db, png: png, thumbnail: png)
        let raw = try Data(contentsOf: directory.appendingPathComponent(file))
        XCTAssertNil(ClipImageLoader.downsample(data: raw, maxPixel: 8))
        XCTAssertEqual(raw[0], ClipCipher.formatVersion)
        XCTAssertNil(db.imageData(named: "missing.vimg"))
    }

    func testTamperedImageFileReadsAsNil() throws {
        let png = makePNG(width: 8, height: 8)
        let (_, file) = try addImage(db, png: png, thumbnail: png)
        let url = directory.appendingPathComponent(file)
        var raw = try Data(contentsOf: url)
        raw[raw.count / 2] ^= 0xff
        try raw.write(to: url)
        XCTAssertNil(db.imageData(named: file))
    }

    func testImageFileCannotBeSwappedBetweenNames() throws {
        let one = try addImage(db, png: makePNG(width: 8, height: 8, seed: 1), thumbnail: makePNG(width: 4, height: 4, seed: 1))
        let two = try addImage(db, png: makePNG(width: 8, height: 8, seed: 2), thumbnail: makePNG(width: 4, height: 4, seed: 2))
        let fm = FileManager.default
        let a = directory.appendingPathComponent(one.file)
        let b = directory.appendingPathComponent(two.file)
        let bytes = try Data(contentsOf: a)
        try fm.removeItem(at: b)
        try bytes.write(to: b)
        XCTAssertNil(db.imageData(named: two.file))
    }

    func testDedupSameTextSameHash() throws {
        let hash = try XCTUnwrap(db.textHash("duplicate me"))
        XCTAssertEqual(db.textHash("duplicate me"), hash)
        XCTAssertNotEqual(db.textHash("duplicate me!"), hash)
        XCTAssertNil(db.id(forHash: hash))
        let id = try addText(db, "duplicate me")
        XCTAssertEqual(db.id(forHash: hash), id)
        XCTAssertThrowsError(try addText(db, "duplicate me"))
        XCTAssertEqual(db.count(), 1)
    }

    func testImageHashUsesKeyedHashOfPNG() throws {
        let png = makePNG(width: 8, height: 8)
        let hash = try XCTUnwrap(db.imageHash(png))
        XCTAssertEqual(hash, db.cipher?.keyedHash(png))
        XCTAssertNotEqual(hash, db.imageHash(makePNG(width: 8, height: 8, seed: 0x99)))
        let (id, _) = try addImage(db, png: png, thumbnail: png)
        XCTAssertEqual(db.id(forHash: hash), id)
    }

    func testDatabaseWithoutCipherRefusesReadsAndWrites() throws {
        let other = FileManager.default.temporaryDirectory.appendingPathComponent("NubrixTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: other) }
        let bare = try track(ClipDatabase(directory: other))
        XCTAssertNil(bare.textHash("x"))
        XCTAssertNil(bare.imageHash(Data("x".utf8)))
        XCTAssertThrowsError(try bare.insert(kind: .text, content: "x", imageFile: nil, width: 0, height: 0, hash: "h", source: nil))
        XCTAssertThrowsError(try bare.writeImage(png: Data("p".utf8), thumbnail: Data("t".utf8)))
        XCTAssertNil(bare.imageData(named: "a.vimg"))
        XCTAssertEqual(bare.count(), 0)
    }

    func testCanaryNeverAppearsInRawFiles() throws {
        let textMarker = "canary-7f3a9c2e-vitrin"
        let sourceMarker = "com.canary.app"
        let pattern = Data((0..<64).map { UInt8(($0 * 7 + 13) % 256) })
        var fakePNG = Data()
        for _ in 0..<16 { fakePNG.append(pattern) }
        XCTAssertEqual(pattern.count, 64)

        let textID = try addText(db, "before \(textMarker) after", source: sourceMarker)
        let imageName = try db.writeImage(png: fakePNG, thumbnail: fakePNG)
        let imageID = try db.insert(kind: .image, content: nil, imageFile: imageName, width: 1, height: 1, hash: try XCTUnwrap(db.imageHash(fakePNG)), source: sourceMarker, bytes: fakePNG.count * 2)

        XCTAssertTrue(exists("vitrin.sqlite-wal"))
        XCTAssertEqual(rawFilesContain(textMarker, in: directory), [])
        XCTAssertEqual(rawFilesContain(sourceMarker, in: directory), [])
        XCTAssertEqual(rawFilesContain(pattern, in: directory), [])

        db.checkpoint()

        XCTAssertEqual(rawFilesContain(textMarker, in: directory), [])
        XCTAssertEqual(rawFilesContain(sourceMarker, in: directory), [])
        XCTAssertEqual(rawFilesContain(pattern, in: directory), [])

        XCTAssertEqual(db.search("vitrin", limit: 10).map(\.id), [textID])
        XCTAssertEqual(db.search("canary-7f3a", limit: 10).map(\.id), [textID])
        XCTAssertEqual(db.imageData(named: imageName), fakePNG)
        XCTAssertEqual(db.summary(id: imageID)?.sourceApp, sourceMarker)
        XCTAssertEqual(db.summary(id: textID)?.sourceApp, sourceMarker)
    }

    func testRawScannerFindsPlaintextControl() throws {
        try Data("xx canary-control xx".utf8).write(to: directory.appendingPathComponent("plain.bin"))
        XCTAssertEqual(rawFilesContain("canary-control", in: directory), ["plain.bin"])
        XCTAssertEqual(rawFilesContain("absent-marker", in: directory), [])
    }

    func testSearchFindsBySubstringAndIgnoresImages() throws {
        let invitation = try addText(db, "Please accept the invitation", now: Date(timeIntervalSince1970: 100))
        let link = try addText(db, "https://vitrin.example/invite", kind: .link, now: Date(timeIntervalSince1970: 200))
        try addImage(db, png: makePNG(width: 8, height: 8), thumbnail: makePNG(width: 4, height: 4), source: "vit.source")
        XCTAssertEqual(db.search("vit", limit: 10).map(\.id), [link, invitation])
        XCTAssertEqual(db.search("INVIT", limit: 10).map(\.id), [link, invitation])
        XCTAssertEqual(db.search("vit accept", limit: 10).map(\.id), [invitation])
        XCTAssertEqual(db.search("zzz", limit: 10), [])
        XCTAssertEqual(db.search("   ", limit: 10).count, 3)
        XCTAssertEqual(db.search("", limit: 2).count, 2)
        XCTAssertEqual(db.search("vit", limit: 1).map(\.id), [link])
    }

    func testSearchIndexFollowsInsertTouchDelete() throws {
        let first = try addText(db, "alpha one", now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(db.search("alpha", limit: 10).map(\.id), [first])
        XCTAssertTrue(db.hasSearchIndex)
        let second = try addText(db, "alpha two", now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(db.search("alpha", limit: 10).map(\.id), [second, first])
        db.touch(id: first, now: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(db.search("alpha", limit: 10).map(\.id), [first, second])
        db.delete(id: first)
        XCTAssertEqual(db.search("alpha", limit: 10).map(\.id), [second])
        db.dropSearchIndex()
        XCTAssertFalse(db.hasSearchIndex)
        XCTAssertEqual(db.search("alpha", limit: 10).map(\.id), [second])
        XCTAssertTrue(db.hasSearchIndex)
    }

    func testExpireRemovesOldUnpinnedAndKeepsPinned() throws {
        let cutoff = Date(timeIntervalSince1970: 5000)
        let oldText = try addText(db, "old text keyword", now: Date(timeIntervalSince1970: 1000))
        let oldPinned = try addText(db, "old pinned keyword", now: Date(timeIntervalSince1970: 1100), pinned: true)
        let fresh = try addText(db, "fresh keyword", now: Date(timeIntervalSince1970: 9000))
        let oldImage = try addImage(db, png: makePNG(width: 8, height: 8, seed: 1), thumbnail: makePNG(width: 4, height: 4, seed: 1), now: Date(timeIntervalSince1970: 1200))
        let pinnedImage = try addImage(db, png: makePNG(width: 8, height: 8, seed: 2), thumbnail: makePNG(width: 4, height: 4, seed: 2), now: Date(timeIntervalSince1970: 1300), pinned: true)
        XCTAssertEqual(db.search("keyword", limit: 10).count, 3)

        XCTAssertEqual(db.expire(olderThan: cutoff), 2)

        XCTAssertNil(db.summary(id: oldText))
        XCTAssertNil(db.summary(id: oldImage.id))
        XCTAssertNotNil(db.summary(id: oldPinned))
        XCTAssertNotNil(db.summary(id: fresh))
        XCTAssertNotNil(db.summary(id: pinnedImage.id))
        XCTAssertFalse(exists(oldImage.file))
        XCTAssertFalse(exists(ClipDatabase.thumbnailName(for: oldImage.file)))
        XCTAssertTrue(exists(pinnedImage.file))
        XCTAssertTrue(exists(ClipDatabase.thumbnailName(for: pinnedImage.file)))
        XCTAssertEqual(Set(db.search("keyword", limit: 10).map(\.id)), [oldPinned, fresh])
        XCTAssertEqual(db.expire(olderThan: cutoff), 0)
    }

    func testTrimMaxUnpinnedKeepsNewestAndPinned() throws {
        var unpinned: [Int64] = []
        for i in 0..<5 {
            unpinned.append(try addText(db, "unpinned \(i)", now: Date(timeIntervalSince1970: Double(1000 + i))))
        }
        let pinned = try addText(db, "pinned oldest", now: Date(timeIntervalSince1970: 10), pinned: true)
        let image = try addImage(db, png: makePNG(width: 8, height: 8), thumbnail: makePNG(width: 4, height: 4), now: Date(timeIntervalSince1970: 500))
        XCTAssertTrue(exists(image.file))

        XCTAssertEqual(db.trim(maxUnpinned: 2), 4)

        XCTAssertEqual(Set(db.summaries().map(\.id)), [unpinned[4], unpinned[3], pinned])
        XCTAssertFalse(exists(image.file))
        XCTAssertFalse(exists(ClipDatabase.thumbnailName(for: image.file)))
        XCTAssertEqual(db.trim(maxUnpinned: 2), 0)
        XCTAssertEqual(db.trim(maxUnpinned: 0), 2)
        XCTAssertEqual(db.summaries().map(\.id), [pinned])
    }

    func testTrimMaxBytesRemovesOldestUnpinnedFirst() throws {
        let pinned = try addText(db, String(repeating: "p", count: 100), now: Date(timeIntervalSince1970: 1), pinned: true)
        let image = try addImage(db, png: Data(repeating: 7, count: 1000), thumbnail: Data(repeating: 8, count: 500), now: Date(timeIntervalSince1970: 100))
        let t1 = try addText(db, String(repeating: "a", count: 10), now: Date(timeIntervalSince1970: 200))
        let t2 = try addText(db, String(repeating: "b", count: 10), now: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(db.totalBytes, 100 + 1500 + 10 + 10)

        XCTAssertEqual(db.trim(maxBytes: 5000), 0)
        XCTAssertEqual(db.trim(maxBytes: 500), 1)
        XCTAssertNil(db.summary(id: image.id))
        XCTAssertFalse(exists(image.file))
        XCTAssertFalse(exists(ClipDatabase.thumbnailName(for: image.file)))
        XCTAssertEqual(Set(db.summaries().map(\.id)), [pinned, t1, t2])

        XCTAssertEqual(db.trim(maxBytes: 115), 1)
        XCTAssertEqual(Set(db.summaries().map(\.id)), [pinned, t2])

        XCTAssertEqual(db.trim(maxBytes: 0), 1)
        XCTAssertEqual(db.summaries().map(\.id), [pinned])
        XCTAssertEqual(db.trim(maxBytes: 0), 0)
    }

    func testDeleteRemovesRowAndEncryptedFiles() throws {
        let image = try addImage(db, png: makePNG(width: 8, height: 8), thumbnail: makePNG(width: 4, height: 4))
        let text = try addText(db, "stays")
        let thumb = ClipDatabase.thumbnailName(for: image.file)
        XCTAssertTrue(exists(image.file) && exists(thumb))
        db.delete(id: image.id)
        XCTAssertNil(db.summary(id: image.id))
        XCTAssertFalse(exists(image.file))
        XCTAssertFalse(exists(thumb))
        XCTAssertNotNil(db.summary(id: text))
        XCTAssertEqual(db.count(), 1)
    }

    func testClearKeepsPinnedWhenAsked() throws {
        let pinnedImage = try addImage(db, png: makePNG(width: 8, height: 8, seed: 1), thumbnail: makePNG(width: 4, height: 4, seed: 1), pinned: true)
        let image = try addImage(db, png: makePNG(width: 8, height: 8, seed: 2), thumbnail: makePNG(width: 4, height: 4, seed: 2))
        let text = try addText(db, "gone")
        db.clear(keepPinned: true)
        XCTAssertEqual(db.summaries().map(\.id), [pinnedImage.id])
        XCTAssertFalse(exists(image.file))
        XCTAssertTrue(exists(pinnedImage.file))
        XCTAssertNil(db.summary(id: text))
        db.clear(keepPinned: false)
        XCTAssertEqual(db.count(), 0)
        XCTAssertFalse(exists(pinnedImage.file))
    }

    func testSweepOrphansRemovesUnreferencedImageFilesOnly() throws {
        let kept = try addImage(db, png: makePNG(width: 8, height: 8), thumbnail: makePNG(width: 4, height: 4))
        let keptThumb = ClipDatabase.thumbnailName(for: kept.file)
        let files = ["orphan.vimg", "orphan.thumb.vimg", "orphan.png", "ORPHAN2.PNG"]
        for name in files + ["key", "notes.txt"] {
            try Data("x".utf8).write(to: directory.appendingPathComponent(name))
        }
        XCTAssertEqual(db.sweepOrphans(), 4)
        for name in files { XCTAssertFalse(exists(name), name) }
        XCTAssertTrue(exists("key"))
        XCTAssertTrue(exists("notes.txt"))
        XCTAssertTrue(exists(kept.file))
        XCTAssertTrue(exists(keptThumb))
        XCTAssertTrue(exists("vitrin.sqlite"))
        XCTAssertEqual(db.sweepOrphans(), 0)
    }

    func testReopenWithSameKeyReadsEverythingBack() throws {
        let png = makePNG(width: 32, height: 32, seed: 0x33)
        let thumbnail = makePNG(width: 8, height: 8, seed: 0x33)
        let text = try addText(db, "persisted text with ünïcode", source: "com.persist.app", now: Date(timeIntervalSince1970: 2000), pinned: true)
        let link = try addText(db, "https://persist.example", kind: .link, now: Date(timeIntervalSince1970: 3000))
        let image = try addImage(db, png: png, thumbnail: thumbnail, source: "com.persist.shot", now: Date(timeIntervalSince1970: 4000))
        let before = db.summaries()
        let keyID = db.storedKeyID
        db.close()
        XCTAssertFalse(db.isOpen)

        let (reopened, wasReset) = try openReady(keys: keys)
        XCTAssertFalse(wasReset)
        XCTAssertEqual(reopened.storedKeyID, keyID)
        XCTAssertEqual(reopened.summaries(), before)
        XCTAssertEqual(reopened.fullText(id: text), "persisted text with ünïcode")
        XCTAssertEqual(reopened.fullText(id: link), "https://persist.example")
        XCTAssertEqual(reopened.imageData(named: image.file), png)
        XCTAssertEqual(reopened.imageData(named: ClipDatabase.thumbnailName(for: image.file)), thumbnail)
        XCTAssertEqual(reopened.search("persist", limit: 10).map(\.id), [link, text])
        XCTAssertEqual(reopened.id(forHash: try XCTUnwrap(reopened.textHash("https://persist.example"))), link)
        XCTAssertEqual(keys.createCount, 1)
    }

    func testClosedDatabaseFailsCleanly() throws {
        let id = try addText(db, "x")
        db.close()
        XCTAssertNil(db.summary(id: id))
        XCTAssertEqual(db.summaries(), [])
        XCTAssertNil(db.fullText(id: id))
        XCTAssertEqual(db.search("x", limit: 5), [])
        XCTAssertEqual(db.count(), 0)
        XCTAssertThrowsError(try addText(db, "y"))
    }

    func testDatabaseDirectoryAndFilePermissions() throws {
        _ = try addText(db, "perm")
        let dir = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((dir[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        let file = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("vitrin.sqlite").path)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let image = try addImage(db, png: makePNG(width: 8, height: 8), thumbnail: makePNG(width: 4, height: 4))
        for name in [image.file, ClipDatabase.thumbnailName(for: image.file)] {
            let attrs = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
            XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600, name)
        }
        if !db.isExcludedFromBackup, !Self.volumeSupportsBackupExclusion(near: directory) {
            throw XCTSkip("This volume does not keep the backup exclusion flag")
        }
        XCTAssertTrue(db.isExcludedFromBackup)
    }

    private static func volumeSupportsBackupExclusion(near directory: URL) -> Bool {
        var probe = directory.deletingLastPathComponent().appendingPathComponent("backup-probe-\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)) != nil else { return false }
        defer { try? FileManager.default.removeItem(at: probe) }
        ClipDatabase.excludeFromBackup(probe)
        probe.removeAllCachedResourceValues()
        return (try? probe.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup ?? false
    }
}
