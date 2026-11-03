import AppKit
import ImageIO
import UniformTypeIdentifiers

struct PreparedClipImage {
    let png: Data
    let thumbnail: Data
    let width: Int
    let height: Int

    var bytes: Int { png.count + thumbnail.count }
}

enum ClipImageProcessor {
    static let maximumBytes = 25 * 1024 * 1024
    static let maximumPixelCount = 60_000_000
    static let reencodePixelCount = 24_000_000
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
        var storedWidth = width
        var storedHeight = height
        if uttype == .png {
            png = data
        } else {
            let image: CGImage
            if width * height > reencodePixelCount {
                let scale = (Double(reencodePixelCount) / Double(width * height)).squareRoot()
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(1, Int(Double(max(width, height)) * scale)),
                    kCGImageSourceShouldCacheImmediately: true
                ]
                guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
                image = scaled
                storedWidth = scaled.width
                storedHeight = scaled.height
            } else {
                guard let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
                image = full
            }
            guard let encoded = encodePNG(image), encoded.count <= maximumBytes else { return nil }
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
        return PreparedClipImage(png: png, thumbnail: thumb, width: storedWidth, height: storedHeight)
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
