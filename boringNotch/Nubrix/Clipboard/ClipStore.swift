import AppKit
import Combine
import Defaults

@MainActor
final class ClipStore: ObservableObject {
    static let shared = ClipStore()
    static let ownPasteboardType = NSPasteboard.PasteboardType("dev.nubrix.vitrin")
    static let maxUnpinnedItems = 2000

    @Published private(set) var items: [ClipItem] = []

    private var database: ClipDatabase?
    private var sweepTimer: Timer?
    private let thumbnailCache = NSCache<NSString, NSImage>()

    private init() {
        thumbnailCache.countLimit = 200
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Nubrix", isDirectory: true).appendingPathComponent("Vitrin", isDirectory: true)
    }

    func start() {
        guard database == nil else { return }
        do {
            database = try ClipDatabase(directory: Self.defaultDirectory)
        } catch {
            return
        }
        sweep()
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweep() }
        }
        RunLoop.main.add(timer, forMode: .common)
        sweepTimer = timer
    }

    func stop() {
        sweepTimer?.invalidate()
        sweepTimer = nil
    }

    var isReady: Bool { database != nil }

    func reload() {
        items = database?.all() ?? []
    }

    func sweep() {
        guard let database else { return }
        let days = Defaults[.vitrinRetentionDays]
        if days > 0 {
            database.expire(olderThan: Date().addingTimeInterval(-Double(days) * 86_400))
        }
        database.trim(maxUnpinned: Self.maxUnpinnedItems)
        reload()
    }

    func search(_ query: String) -> [ClipItem] {
        database?.search(query) ?? []
    }

    func addText(_ text: String, source: String?) {
        guard let database, let classified = ClipClassifier.classify(text) else { return }
        let hash = ClipImageProcessor.textHash(classified.content)
        if let existing = database.id(forHash: hash) {
            database.touch(id: existing)
        } else {
            guard (try? database.insert(kind: classified.kind, content: classified.content, imageFile: nil, width: 0, height: 0, hash: hash, source: source)) != nil else { return }
        }
        reload()
    }

    func addImage(_ image: PreparedClipImage, source: String?) {
        guard let database else { return }
        if let existing = database.id(forHash: image.hash) {
            database.touch(id: existing)
        } else {
            guard let file = try? database.writeImage(png: image.png, thumbnail: image.thumbnail) else { return }
            if (try? database.insert(kind: .image, content: nil, imageFile: file, width: image.width, height: image.height, hash: image.hash, source: source)) == nil {
                database.removeFiles([file])
                return
            }
        }
        reload()
    }

    func copy(_ item: ClipItem) {
        guard let database else { return }
        let pb = NSPasteboard.general
        switch item.kind {
        case .text, .link:
            guard let text = item.text else { return }
            pb.declareTypes([.string, Self.ownPasteboardType], owner: nil)
            pb.setString(text, forType: .string)
        case .image:
            guard let file = item.imageFile,
                  let data = try? Data(contentsOf: database.directory.appendingPathComponent(file)) else { return }
            var types: [NSPasteboard.PasteboardType] = [.png, Self.ownPasteboardType]
            let tiff = NSImage(data: data)?.tiffRepresentation
            if tiff != nil { types.insert(.tiff, at: 1) }
            pb.declareTypes(types, owner: nil)
            pb.setData(data, forType: .png)
            if let tiff { pb.setData(tiff, forType: .tiff) }
        }
        pb.setData(Data([1]), forType: Self.ownPasteboardType)
        ClipboardMonitor.shared.acknowledge(changeCount: pb.changeCount)
        database.touch(id: item.id)
        reload()
    }

    func copyTransformed(_ string: String) {
        let pb = NSPasteboard.general
        pb.declareTypes([.string, Self.ownPasteboardType], owner: nil)
        pb.setString(string, forType: .string)
        pb.setData(Data([1]), forType: Self.ownPasteboardType)
        ClipboardMonitor.shared.acknowledge(changeCount: pb.changeCount)
    }

    func fullImage(for item: ClipItem) -> NSImage? {
        guard let file = item.imageFile, let database else { return nil }
        return NSImage(contentsOf: database.directory.appendingPathComponent(file))
    }

    func togglePin(_ item: ClipItem) {
        database?.setPinned(id: item.id, !item.pinned)
        reload()
    }

    func delete(_ item: ClipItem) {
        database?.delete(id: item.id)
        reload()
    }

    func clearHistory() {
        database?.clear(keepPinned: true)
        thumbnailCache.removeAllObjects()
        reload()
    }

    func thumbnail(for item: ClipItem) -> NSImage? {
        guard let file = item.thumbnailFile, let database else { return nil }
        if let cached = thumbnailCache.object(forKey: file as NSString) { return cached }
        guard let image = NSImage(contentsOf: database.directory.appendingPathComponent(file)) else { return nil }
        thumbnailCache.setObject(image, forKey: file as NSString)
        return image
    }
}
