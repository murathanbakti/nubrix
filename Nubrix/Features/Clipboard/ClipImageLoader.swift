import AppKit
import ImageIO
import UniformTypeIdentifiers

final class ClipCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

enum ClipImageLoader {
    static let thumbnailQueue = DispatchQueue(label: "dev.nubrix.vitrin.thumbnails", qos: .userInitiated)
    static let previewQueue = DispatchQueue(label: "dev.nubrix.vitrin.preview", qos: .userInitiated)

    static func downsample(url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func downsample(url: URL, maxPixel: Int, on queue: DispatchQueue) async -> CGImage? {
        let flag = ClipCancelFlag()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
                queue.async {
                    if flag.isCancelled {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(returning: downsample(url: url, maxPixel: maxPixel))
                    }
                }
            }
        } onCancel: {
            flag.cancel()
        }
    }

    static func cost(of image: CGImage) -> Int {
        image.bytesPerRow * image.height
    }

    static func tiffData(from url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let out = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(out, UTType.tiff.identifier as CFString, 1, nil) else { return nil }
        let properties: [CFString: Any] = [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5]]
        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}

final class ClipLazyImagePasteboardOwner: NSObject, NSPasteboardTypeOwner, @unchecked Sendable {
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func pasteboard(_ pasteboard: NSPasteboard, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .tiff, let data = ClipImageLoader.tiffData(from: url) else { return }
        pasteboard.setData(data, forType: .tiff)
    }
}
