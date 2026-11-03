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

    static func downsample(data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func downsample(load: @escaping @Sendable () -> Data?, maxPixel: Int, on queue: DispatchQueue) async -> CGImage? {
        let flag = ClipCancelFlag()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
                queue.async {
                    if flag.isCancelled {
                        continuation.resume(returning: nil)
                    } else if let data = load() {
                        continuation.resume(returning: downsample(data: data, maxPixel: maxPixel))
                    } else {
                        continuation.resume(returning: nil)
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
}
