import AppKit
import Combine
import Defaults
import os
import UniformTypeIdentifiers

private let storeLog = Logger(subsystem: "dev.nubrix.app", category: "vitrin")

enum VitrinVaultState: Equatable {
    case off
    case opening
    case ready
    case locked(OSStatus)
    case failed(String)
}

@MainActor
final class ClipStore: ObservableObject {
    static let shared = ClipStore()
    static let ownPasteboardType = NSPasteboard.PasteboardType("dev.nubrix.vitrin")
    static let maxUnpinnedItems = 2000
    static let maxTotalBytes: Int64 = 1_073_741_824
    static let listLimit = 1000
    static let searchLimit = 300
    static let thumbnailPixels = 384
    static let previewPixels = 1600
    nonisolated static let dragFolderName = "NubrixDrag"
    nonisolated static let dragCleanupDelay: TimeInterval = 300

    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var vaultState: VitrinVaultState = .off

    nonisolated let queue = DispatchQueue(label: "dev.nubrix.vitrin.database", qos: .utility)

    private var database: ClipDatabase?
    private var imageVault: ClipImageVault?
    private var sweepTimer: Timer?
    private var idleTimer: Timer?
    private var generation = 0
    private var directory = ClipStore.defaultDirectory
    private var keys: VitrinKeyProviding?
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private var previewCache: (id: Int64, image: NSImage)?
    private var lastTextHash: String?
    private var lastTextID: Int64?
    private(set) var fullReloadCount = 0

    private init() {
        thumbnailCache.countLimit = 300
        thumbnailCache.totalCostLimit = 32 * 1024 * 1024
    }

    nonisolated static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        #if DEBUG
        let folder = "Vitrin-Debug"
        #else
        let folder = "Vitrin"
        #endif
        return base.appendingPathComponent("Nubrix", isDirectory: true).appendingPathComponent(folder, isDirectory: true)
    }

    nonisolated static var dragRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(dragFolderName, isDirectory: true)
    }

    func start(directory: URL = ClipStore.defaultDirectory, keys: VitrinKeyProviding? = nil) {
        guard vaultState == .off else { return }
        let root = Self.dragRoot
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(at: root)
        }
        let provider = keys ?? VitrinKeyStores.makeDefault(directory: directory)
        self.directory = directory
        self.keys = provider
        beginOpen { ClipVault.open(directory: directory, keys: provider) }
    }

    private func beginOpen(_ work: @escaping @Sendable () -> ClipVaultOpenResult) {
        generation += 1
        let current = generation
        vaultState = .opening
        queue.async {
            let result = work()
            Task { @MainActor in ClipStore.shared.finishOpen(result, generation: current) }
        }
    }

    private func finishOpen(_ result: ClipVaultOpenResult, generation current: Int) {
        guard current == generation else {
            if case .ready(let stale, _) = result {
                queue.async { stale.close() }
            }
            return
        }
        switch result {
        case .ready(let db, let wasReset):
            database = db
            imageVault = db.imageVault
            if wasReset { Defaults[.vitrinKeyResetNotice] = true }
            vaultState = .ready
            queue.async { _ = db.runDeferredMigration() }
            runMigration(db)
            Task { await reloadList() }
            startSweepTimer()
        case .locked(let status):
            vaultState = .locked(status)
        case .failed(let message):
            vaultState = .failed(message)
        }
    }

    private nonisolated func runMigration(_ db: ClipDatabase) {
        queue.async { [self] in
            guard db.isOpen else { return }
            do {
                if try db.migrateEncryptionBatch() {
                    runMigration(db)
                    return
                }
            } catch {
                storeLog.error("Vitrin encryption migration stopped: \(String(describing: error), privacy: .public)")
                return
            }
            _ = db.finishEncryptionMigration()
            Task { @MainActor in ClipStore.shared.migrationFinished(db) }
        }
    }

    private func migrationFinished(_ db: ClipDatabase) {
        guard database === db else { return }
        sweep(reloadAlways: true)
    }

    private func startSweepTimer() {
        sweepTimer?.invalidate()
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweep() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        sweepTimer = timer
    }

    func retryUnlock() {
        switch vaultState {
        case .locked, .failed: break
        default: return
        }
        guard let keys else { return }
        let directory = self.directory
        beginOpen { ClipVault.open(directory: directory, keys: keys) }
    }

    func retryIfKeychainLocked() {
        guard vaultState == .locked(errSecInteractionNotAllowed) else { return }
        retryUnlock()
    }

    func resetHistoryAndKey() {
        guard let keys, vaultState != .off else { return }
        let old = database
        database = nil
        imageVault = nil
        stop()
        clearCaches()
        items = []
        Defaults[.vitrinKeyResetNotice] = false
        let directory = self.directory
        beginOpen {
            old?.close()
            return ClipVault.reset(directory: directory, keys: keys)
        }
    }

    func stop() {
        sweepTimer?.invalidate()
        sweepTimer = nil
    }

    func shutdown() {
        stop()
        idleTimer?.invalidate()
        idleTimer = nil
        generation += 1
        if let old = database {
            queue.async { old.close() }
        }
        database = nil
        imageVault = nil
        vaultState = .off
        items = []
        clearCaches()
    }

    private func clearCaches() {
        thumbnailCache.removeAllObjects()
        previewCache = nil
        lastTextHash = nil
        lastTextID = nil
    }

    var isReady: Bool { vaultState == .ready && database != nil }

    func dropSearchIndex() {
        enqueue { $0.dropSearchIndex() }
    }

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable (ClipDatabase) -> T) async -> T? {
        guard let database else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            queue.async { continuation.resume(returning: work(database)) }
        }
    }

    private func enqueue(_ work: @escaping @Sendable (ClipDatabase) -> Void) {
        guard let database else { return }
        queue.async { work(database) }
    }

    func reloadList() async {
        fullReloadCount += 1
        let limit = Self.listLimit
        if let list = await onQueue({ $0.summaries(limit: limit) }), database != nil {
            items = list
        }
    }

    func sweep(reloadAlways: Bool = false) {
        guard database != nil else { return }
        let days = Defaults[.vitrinRetentionDays]
        let maxUnpinned = Self.maxUnpinnedItems
        let maxBytes = Self.maxTotalBytes
        Task {
            let removed = await onQueue { db -> Int in
                var count = 0
                if days > 0 {
                    count += db.expire(olderThan: Date().addingTimeInterval(-Double(days) * 86_400))
                }
                count += db.trim(maxUnpinned: maxUnpinned)
                count += db.trim(maxBytes: maxBytes)
                return count
            }
            if reloadAlways || (removed ?? 0) > 0 {
                await reloadList()
            }
        }
    }

    func search(_ query: String) async -> [ClipItem] {
        let limit = Self.searchLimit
        restartIdleTimer()
        return await onQueue({ $0.search(query, limit: limit) }) ?? []
    }

    private func restartIdleTimer() {
        idleTimer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dropSearchIndex() }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    func fullText(for item: ClipItem, maxChars: Int? = nil) async -> String? {
        if item.isTextComplete, let preview = item.preview {
            guard let maxChars else { return preview }
            return String(preview.prefix(maxChars))
        }
        let id = item.id
        return await onQueue({ $0.fullText(id: id, maxChars: maxChars) }) ?? nil
    }

    func addText(_ classified: ClipClassification, source: String?) {
        guard database != nil else { return }
        let previousHash = lastTextHash
        let previousID = lastTextID
        let topID = items.first?.id
        Task {
            let result = await onQueue { db -> (hash: String, item: ClipItem)? in
                guard let hash = db.textHash(classified.content) else { return nil }
                if hash == previousHash, let previousID, previousID == topID { return nil }
                let id: Int64
                if let existing = db.id(forHash: hash) {
                    db.touch(id: existing)
                    id = existing
                } else {
                    guard let inserted = try? db.insert(kind: classified.kind, content: classified.content, imageFile: nil, width: 0, height: 0, hash: hash, source: source) else { return nil }
                    id = inserted
                }
                guard let item = db.summary(id: id) else { return nil }
                return (hash, item)
            } ?? nil
            guard let result, database != nil else { return }
            lastTextHash = result.hash
            lastTextID = result.item.id
            place(result.item)
        }
    }

    @discardableResult
    func addImage(_ image: PreparedClipImage, source: String?) async -> ClipItem? {
        let created = await onQueue { db -> (item: ClipItem, isNew: Bool)? in
            guard let hash = db.imageHash(image.png) else { return nil }
            if let existing = db.id(forHash: hash) {
                db.touch(id: existing)
                return db.summary(id: existing).map { ($0, false) }
            }
            guard let file = try? db.writeImage(png: image.png, thumbnail: image.thumbnail) else { return nil }
            guard let inserted = try? db.insert(kind: .image, content: nil, imageFile: file, width: image.width, height: image.height, hash: hash, source: source, bytes: image.bytes) else {
                db.removeFiles([file])
                return nil
            }
            return db.summary(id: inserted).map { ($0, true) }
        } ?? nil
        guard let created, database != nil else { return nil }
        place(created.item)
        if created.isNew { sweep() }
        return created.item
    }

    private func place(_ item: ClipItem) {
        var next = items
        next.removeAll { $0.id == item.id }
        let index = next.firstIndex { existing in
            !(existing.lastUsedAt > item.lastUsedAt || (existing.lastUsedAt == item.lastUsedAt && existing.id > item.id))
        } ?? next.count
        next.insert(item, at: index)
        if next.count > Self.listLimit { next.removeLast(next.count - Self.listLimit) }
        items = next
    }

    private func markUsed(id: Int64) {
        let now = Date()
        if var item = items.first(where: { $0.id == id }) {
            item.lastUsedAt = now
            place(item)
        }
        enqueue { $0.touch(id: id, now: now) }
    }

    func itemProvider(for item: ClipItem) -> NSItemProvider {
        switch item.kind {
        case .text, .link:
            if item.isTextComplete {
                return NSItemProvider(object: item.previewOrEmpty as NSString)
            }
            guard let database else { return NSItemProvider() }
            let id = item.id
            let queue = self.queue
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
                queue.async {
                    completion(database.fullText(id: id)?.data(using: .utf8), nil)
                }
                return nil
            }
            return provider
        case .image:
            guard let file = item.imageFile, let vault = imageVault else { return NSItemProvider() }
            let name = Self.dragFileName(for: item)
            let provider = NSItemProvider()
            provider.suggestedName = (name as NSString).deletingPathExtension
            provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
                do {
                    guard let data = vault.read(named: file) else { throw CocoaError(.fileReadNoSuchFile) }
                    completion(try Self.namedDragCopy(data: data, named: name), false, nil)
                } catch {
                    completion(nil, false, error)
                }
                return nil
            }
            provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                if let data = vault.read(named: file) {
                    completion(data, nil)
                } else {
                    completion(nil, CocoaError(.fileReadNoSuchFile))
                }
                return nil
            }
            return provider
        }
    }

    nonisolated static func dragFileName(for item: ClipItem) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let prefix = item.isScreenshot ? "Screenshot" : "Image"
        return "\(prefix) \(formatter.string(from: item.createdAt)).png"
    }

    nonisolated static func namedDragCopy(data: Data, named name: String, root: URL = ClipStore.dragRoot, cleanupAfter delay: TimeInterval = ClipStore.dragCleanupDelay) throws -> URL {
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = folder.appendingPathComponent(name)
        try data.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            try? FileManager.default.removeItem(at: folder)
        }
        return destination
    }

    func copy(_ item: ClipItem) {
        switch item.kind {
        case .text, .link:
            if item.isTextComplete, let text = item.preview {
                writeText(text)
                markUsed(id: item.id)
            } else {
                Task {
                    guard let text = await fullText(for: item) else { return }
                    writeText(text)
                    markUsed(id: item.id)
                }
            }
        case .image:
            guard let file = item.imageFile, let vault = imageVault else { return }
            let id = item.id
            Task {
                let data = await Task.detached(priority: .userInitiated) {
                    vault.read(named: file)
                }.value
                guard let data else { return }
                let pb = NSPasteboard.general
                pb.declareTypes([.png, Self.ownPasteboardType], owner: nil)
                pb.setData(data, forType: .png)
                pb.setData(Data([1]), forType: Self.ownPasteboardType)
                ClipboardMonitor.shared.acknowledge(changeCount: pb.changeCount)
                markUsed(id: id)
            }
        }
    }

    private func writeText(_ text: String) {
        let pb = NSPasteboard.general
        pb.declareTypes([.string, Self.ownPasteboardType], owner: nil)
        pb.setString(text, forType: .string)
        pb.setData(Data([1]), forType: Self.ownPasteboardType)
        ClipboardMonitor.shared.acknowledge(changeCount: pb.changeCount)
    }

    func copyTransformed(_ string: String) {
        writeText(string)
    }

    func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let pinned = !items[index].pinned
        var next = items
        next[index].pinned = pinned
        items = next
        let id = item.id
        enqueue { $0.setPinned(id: id, pinned) }
    }

    func delete(_ item: ClipItem) {
        let id = item.id
        items = items.filter { $0.id != id }
        if let file = item.thumbnailFile { thumbnailCache.removeObject(forKey: file as NSString) }
        if previewCache?.id == id { previewCache = nil }
        ClipInsightCache.shared.forget(id: id)
        if lastTextID == id { lastTextID = nil }
        enqueue { $0.delete(id: id) }
    }

    func clearHistory() {
        items = items.filter(\.pinned)
        thumbnailCache.removeAllObjects()
        previewCache = nil
        lastTextID = nil
        ClipInsightCache.shared.removeAll()
        enqueue { $0.clear(keepPinned: true) }
    }

    func cachedThumbnail(for item: ClipItem) -> NSImage? {
        guard let file = item.thumbnailFile else { return nil }
        return thumbnailCache.object(forKey: file as NSString)
    }

    func thumbnail(for item: ClipItem) async -> NSImage? {
        guard let file = item.thumbnailFile, let vault = imageVault else { return nil }
        if let cached = thumbnailCache.object(forKey: file as NSString) { return cached }
        guard let cgImage = await ClipImageLoader.downsample(load: { vault.read(named: file) }, maxPixel: Self.thumbnailPixels, on: ClipImageLoader.thumbnailQueue) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        thumbnailCache.setObject(image, forKey: file as NSString, cost: ClipImageLoader.cost(of: cgImage))
        return image
    }

    func cachedPreview(for item: ClipItem) -> NSImage? {
        guard let previewCache, previewCache.id == item.id else { return nil }
        return previewCache.image
    }

    func previewImage(for item: ClipItem) async -> NSImage? {
        if let cached = cachedPreview(for: item) { return cached }
        guard let file = item.imageFile, let vault = imageVault else { return nil }
        guard let cgImage = await ClipImageLoader.downsample(load: { vault.read(named: file) }, maxPixel: Self.previewPixels, on: ClipImageLoader.previewQueue) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        if !Task.isCancelled { previewCache = (item.id, image) }
        return image
    }
}
