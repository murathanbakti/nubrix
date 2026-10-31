import AppKit
import Combine
import Defaults
import UniformTypeIdentifiers

@MainActor
final class ClipStore: ObservableObject {
    static let shared = ClipStore()
    static let ownPasteboardType = NSPasteboard.PasteboardType("dev.nubrix.vitrin")
    static let maxUnpinnedItems = 2000
    static let listLimit = 1000
    static let searchLimit = 300
    static let thumbnailPixels = 384
    static let previewPixels = 1600
    nonisolated static let dragFolderName = "NubrixDrag"
    nonisolated static let dragCleanupDelay: TimeInterval = 300

    @Published private(set) var items: [ClipItem] = []

    nonisolated let queue = DispatchQueue(label: "dev.nubrix.vitrin.database", qos: .utility)

    private var database: ClipDatabase?
    private var sweepTimer: Timer?
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private var previewCache: (id: Int64, image: NSImage)?
    private var pasteboardOwner: ClipLazyImagePasteboardOwner?
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
        return base.appendingPathComponent("Nubrix", isDirectory: true).appendingPathComponent("Vitrin", isDirectory: true)
    }

    nonisolated static var dragRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(dragFolderName, isDirectory: true)
    }

    func start(directory: URL = ClipStore.defaultDirectory) {
        guard database == nil else { return }
        let root = Self.dragRoot
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(at: root)
        }
        do {
            database = try ClipDatabase(directory: directory)
        } catch {
            return
        }
        enqueue { $0.runDeferredMigration() }
        sweep(reloadAlways: true)
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweep() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        sweepTimer = timer
    }

    func stop() {
        sweepTimer?.invalidate()
        sweepTimer = nil
    }

    var isReady: Bool { database != nil }

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
        if let list = await onQueue({ $0.summaries(limit: limit) }) {
            items = list
        }
    }

    func sweep(reloadAlways: Bool = false) {
        guard database != nil else { return }
        let days = Defaults[.vitrinRetentionDays]
        let maxUnpinned = Self.maxUnpinnedItems
        Task {
            let removed = await onQueue { db -> Int in
                var count = 0
                if days > 0 {
                    count += db.expire(olderThan: Date().addingTimeInterval(-Double(days) * 86_400))
                }
                count += db.trim(maxUnpinned: maxUnpinned)
                return count
            }
            if reloadAlways || (removed ?? 0) > 0 {
                await reloadList()
            }
        }
    }

    func search(_ query: String) async -> [ClipItem] {
        let limit = Self.searchLimit
        return await onQueue({ $0.search(query, limit: limit) }) ?? []
    }

    func fullText(for item: ClipItem, maxChars: Int? = nil) async -> String? {
        if item.isTextComplete, let preview = item.preview {
            guard let maxChars else { return preview }
            return String(preview.prefix(maxChars))
        }
        let id = item.id
        return await onQueue({ $0.fullText(id: id, maxChars: maxChars) }) ?? nil
    }

    func addText(_ classified: ClipClassification, hash: String, source: String?) {
        guard database != nil else { return }
        if hash == lastTextHash, let id = lastTextID, items.first?.id == id { return }
        Task {
            let item = await onQueue { db -> ClipItem? in
                let id: Int64
                if let existing = db.id(forHash: hash) {
                    db.touch(id: existing)
                    id = existing
                } else {
                    guard let inserted = try? db.insert(kind: classified.kind, content: classified.content, imageFile: nil, width: 0, height: 0, hash: hash, source: source) else { return nil }
                    id = inserted
                }
                return db.summary(id: id)
            } ?? nil
            guard let item else { return }
            lastTextHash = hash
            lastTextID = item.id
            place(item)
        }
    }

    @discardableResult
    func addImage(_ image: PreparedClipImage, source: String?) async -> ClipItem? {
        let item = await onQueue { db -> ClipItem? in
            if let existing = db.id(forHash: image.hash) {
                db.touch(id: existing)
                return db.summary(id: existing)
            }
            guard let file = try? db.writeImage(png: image.png, thumbnail: image.thumbnail) else { return nil }
            guard let inserted = try? db.insert(kind: .image, content: nil, imageFile: file, width: image.width, height: image.height, hash: image.hash, source: source) else {
                db.removeFiles([file])
                return nil
            }
            return db.summary(id: inserted)
        } ?? nil
        if let item { place(item) }
        return item
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
            guard let file = item.imageFile, let database else { return NSItemProvider() }
            let url = database.directory.appendingPathComponent(file)
            let name = Self.dragFileName(for: item)
            let provider = NSItemProvider()
            provider.suggestedName = (name as NSString).deletingPathExtension
            provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
                do {
                    completion(try Self.namedDragCopy(of: url, named: name), false, nil)
                } catch {
                    completion(nil, false, error)
                }
                return nil
            }
            provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                do {
                    completion(try Data(contentsOf: url, options: .mappedIfSafe), nil)
                } catch {
                    completion(nil, error)
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

    nonisolated static func namedDragCopy(of source: URL, named name: String, root: URL = ClipStore.dragRoot, cleanupAfter delay: TimeInterval = ClipStore.dragCleanupDelay) throws -> URL {
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = folder.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: destination)
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
            guard let file = item.imageFile, let directory = database?.directory else { return }
            let url = directory.appendingPathComponent(file)
            let id = item.id
            Task {
                let data = await Task.detached(priority: .userInitiated) {
                    try? Data(contentsOf: url, options: .mappedIfSafe)
                }.value
                guard let data else { return }
                let owner = ClipLazyImagePasteboardOwner(url: url)
                pasteboardOwner = owner
                let pb = NSPasteboard.general
                pb.declareTypes([.png, .tiff, Self.ownPasteboardType], owner: owner)
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
        guard let file = item.thumbnailFile, let directory = database?.directory else { return nil }
        if let cached = thumbnailCache.object(forKey: file as NSString) { return cached }
        let url = directory.appendingPathComponent(file)
        guard let cgImage = await ClipImageLoader.downsample(url: url, maxPixel: Self.thumbnailPixels, on: ClipImageLoader.thumbnailQueue) else { return nil }
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
        guard let file = item.imageFile, let directory = database?.directory else { return nil }
        let url = directory.appendingPathComponent(file)
        guard let cgImage = await ClipImageLoader.downsample(url: url, maxPixel: Self.previewPixels, on: ClipImageLoader.previewQueue) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        if !Task.isCancelled { previewCache = (item.id, image) }
        return image
    }
}
