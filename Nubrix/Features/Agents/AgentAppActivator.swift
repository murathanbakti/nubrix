import AppKit

enum AgentAppActivator {
    @MainActor private static var iconCache: [String: NSImage] = [:]

    @MainActor
    static func activate(bundleID: String?) {
        guard let bundleID, !bundleID.isEmpty,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        app.activate()
    }

    @MainActor
    static func icon(bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let cached = iconCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[bundleID] = image
        return image
    }
}
