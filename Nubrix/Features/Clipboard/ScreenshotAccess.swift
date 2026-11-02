import AppKit
import Combine
import Defaults

@MainActor
final class ScreenshotAccess: ObservableObject {
    static let shared = ScreenshotAccess()

    @Published private(set) var folder: URL?

    static let bookmarkCreationOptions: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]

    private var scopedURL: URL?

    private init() {}

    var hasAccess: Bool { folder != nil }

    var detectedFolder: URL { ScreenshotDetection.detectedFolder() }

    func restore() {
        guard let data = Defaults[.vitrinScreenshotFolderBookmark] else {
            release()
            return
        }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            Defaults[.vitrinScreenshotFolderBookmark] = nil
            release()
            return
        }
        if scopedURL?.path != url.path {
            release()
            guard url.startAccessingSecurityScopedResource() else {
                Defaults[.vitrinScreenshotFolderBookmark] = nil
                folder = nil
                return
            }
            scopedURL = url
        }
        if stale || !Defaults[.vitrinScreenshotBookmarkReadOnly],
           let fresh = try? url.bookmarkData(options: Self.bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
            Defaults[.vitrinScreenshotFolderBookmark] = fresh
            Defaults[.vitrinScreenshotBookmarkReadOnly] = true
        }
        if folder?.path != url.path { folder = url }
    }

    @discardableResult
    func requestAccess() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder ?? detectedFolder
        panel.prompt = "Allow"
        panel.title = "Screenshot folder"
        panel.message = "Choose the folder where macOS saves your screenshots so Vitrin can show them. Nubrix only reads new screenshots there."
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        guard let data = try? url.bookmarkData(options: Self.bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) else { return false }
        Defaults[.vitrinScreenshotFolderBookmark] = data
        Defaults[.vitrinScreenshotBookmarkReadOnly] = true
        Defaults[.vitrinScreenshotPromptDismissed] = false
        restore()
        return folder != nil
    }

    func release() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        folder = nil
    }
}
