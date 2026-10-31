import Foundation

enum ScreenshotDetection {
    static let sourceID = "com.apple.screenshot"
    static let captureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif"]
    static let creationTolerance: TimeInterval = 15

    static var realHome: String {
        getpwuid(getuid()).flatMap { String(validatingUTF8: $0.pointee.pw_dir) } ?? NSHomeDirectory()
    }

    static func isCandidateName(_ name: String) -> Bool {
        guard !name.hasPrefix(".") else { return false }
        return imageExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    static func newCandidates(current: [String], known: Set<String>) -> [String] {
        current.filter { !known.contains($0) && isCandidateName($0) }.sorted()
    }

    static func isScreenCapture(atPath path: String) -> Bool {
        let size = getxattr(path, captureAttribute, nil, 0, 0, XATTR_NOFOLLOW)
        guard size >= 0 else { return false }
        guard size > 0 else { return true }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(path, captureAttribute, &buffer, size, 0, XATTR_NOFOLLOW)
        guard read > 0 else { return true }
        let data = Data(buffer.prefix(read))
        guard let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return true }
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.intValue != 0 }
        return true
    }

    static func resolveFolder(preference: String?, home: String, isDirectory: (String) -> Bool) -> URL {
        let desktop = URL(fileURLWithPath: home).appendingPathComponent("Desktop", isDirectory: true)
        guard var path = preference?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return desktop }
        if path == "~" {
            path = home
        } else if path.hasPrefix("~/") {
            path = home + String(path.dropFirst(1))
        }
        guard path.hasPrefix("/"), isDirectory(path) else { return desktop }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func detectedFolder() -> URL {
        let value = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String
        return resolveFolder(preference: value, home: realHome) { path in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    static func displayPath(_ url: URL) -> String {
        let home = realHome
        let path = url.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

enum ScreenshotVerdict: Equatable {
    case waiting
    case ready
    case gone
    case rejected
}

struct ScreenshotCandidate {
    let path: String
    let watchStart: Date
    private var lastSize: Int64 = -1
    private var stableReads = 0
    private var checkedDate = false

    static let requiredStableReads = 2
    static let rejectionStableReads = 4

    init(path: String, watchStart: Date) {
        self.path = path
        self.watchStart = watchStart
    }

    mutating func poll() -> ScreenshotVerdict {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return .gone }
        guard (attrs[.type] as? FileAttributeType) == .typeRegular else { return .rejected }
        if !checkedDate {
            checkedDate = true
            if let created = attrs[.creationDate] as? Date,
               created < watchStart.addingTimeInterval(-ScreenshotDetection.creationTolerance) { return .rejected }
        }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if size > 0, size == lastSize {
            stableReads += 1
        } else {
            stableReads = 0
            lastSize = size
        }
        guard stableReads >= Self.requiredStableReads else { return .waiting }
        if ScreenshotDetection.isScreenCapture(atPath: path) { return .ready }
        return stableReads >= Self.rejectionStableReads ? .rejected : .waiting
    }
}
