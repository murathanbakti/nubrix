import Foundation

enum ClipKind: Int, CaseIterable {
    case image = 0
    case text = 1
    case link = 2
}

struct ClipItem: Identifiable, Equatable {
    let id: Int64
    var kind: ClipKind
    var text: String?
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

    var linkURL: URL? {
        guard kind == .link, let text else { return nil }
        return URL(string: text)
    }
}
