import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

struct PreparedClipImage {
    let png: Data
    let thumbnail: Data
    let width: Int
    let height: Int
    let hash: String
}

enum ClipImageProcessor {
    static let maximumBytes = 25 * 1024 * 1024
    static let maximumPixelCount = 60_000_000
    static let thumbnailPixels = 480

    static func prepare(_ data: Data) -> PreparedClipImage? {
        guard !data.isEmpty, data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              let uttype = UTType(type), uttype.conforms(to: .image),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0, width <= maximumPixelCount / height else { return nil }

        let png: Data
        if uttype == .png {
            png = data
        } else {
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let encoded = encodePNG(image) else { return nil }
            png = encoded
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixels,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary),
              let thumb = encodePNG(thumbImage) else { return nil }
        let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        return PreparedClipImage(png: png, thumbnail: thumb, width: width, height: height, hash: hash)
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    static func textHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
