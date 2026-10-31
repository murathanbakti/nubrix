import AppKit
import Combine
import Defaults
import UniformTypeIdentifiers

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
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("NubrixDrag", isDirectory: true))
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

    @discardableResult
    func addImage(_ image: PreparedClipImage, source: String?) -> Int64? {
        guard let database else { return nil }
        let id: Int64
        if let existing = database.id(forHash: image.hash) {
            database.touch(id: existing)
            id = existing
        } else {
            guard let file = try? database.writeImage(png: image.png, thumbnail: image.thumbnail) else { return nil }
            guard let inserted = try? database.insert(kind: .image, content: nil, imageFile: file, width: image.width, height: image.height, hash: image.hash, source: source) else {
                database.removeFiles([file])
                return nil
            }
            id = inserted
        }
        reload()
        return id
    }

    func itemProvider(for item: ClipItem) -> NSItemProvider {
        switch item.kind {
        case .text, .link:
            return NSItemProvider(object: (item.text ?? "") as NSString)
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
                    completion(try Data(contentsOf: url), nil)
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

    nonisolated static func namedDragCopy(of source: URL, named name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NubrixDrag", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = folder.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
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
