import Foundation

struct ClipItem: Identifiable, Equatable, Sendable {
    let id: Int64
    var kind: ClipKind
    var preview: String?
    var textLength: Int
    var imageFile: String?
    var imageWidth: Int
    var imageHeight: Int
    var sourceApp: String?
    var createdAt: Date
    var lastUsedAt: Date
    var pinned: Bool

    var thumbnailFile: String? {
        guard let imageFile else { return nil }
        return ClipDatabase.thumbnailName(for: imageFile)
    }

    var isScreenshot: Bool {
        kind == .image && sourceApp == ScreenshotDetection.sourceID
    }

    var isTextComplete: Bool {
        textLength <= ClipDatabase.previewLength
    }

    var previewOrEmpty: String {
        preview ?? ""
    }
}
