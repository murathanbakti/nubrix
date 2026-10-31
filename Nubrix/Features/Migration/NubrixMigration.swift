import Foundation

enum NubrixMigration {
    static let versionKey = "nubrixMigrationVersion"
    static let currentVersion = 1

    static let defaultsKeys: [(old: String, new: String)] = [
        ("boringShelf", "nubrixShelf")
    ]

    static let supportFolders: [(old: [String], new: [String])] = [
        (["boringNotch", "Shelf"], ["Nubrix", "Shelf"])
    ]

    static func run(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        supportDirectory: URL? = nil
    ) {
        guard defaults.integer(forKey: versionKey) < currentVersion else { return }
        migrateDefaults(defaults)
        let base = supportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let base {
            migrateSupportFolders(in: base, fileManager: fileManager)
        }
        defaults.set(currentVersion, forKey: versionKey)
    }

    static func migrateDefaults(_ defaults: UserDefaults) {
        for pair in defaultsKeys {
            guard let value = defaults.object(forKey: pair.old) else { continue }
            if defaults.object(forKey: pair.new) == nil {
                defaults.set(value, forKey: pair.new)
            }
            defaults.removeObject(forKey: pair.old)
        }
    }

    static func migrateSupportFolders(in base: URL, fileManager fm: FileManager) {
        for pair in supportFolders {
            let source = pair.old.reduce(base) { $0.appendingPathComponent($1, isDirectory: true) }
            let target = pair.new.reduce(base) { $0.appendingPathComponent($1, isDirectory: true) }
            guard fm.fileExists(atPath: source.path), !fm.fileExists(atPath: target.path) else { continue }
            do {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: source, to: target)
            } catch {
                continue
            }
            removeIfEmpty(source.deletingLastPathComponent(), fileManager: fm, stopAt: base)
        }
    }

    private static func removeIfEmpty(_ directory: URL, fileManager fm: FileManager, stopAt base: URL) {
        guard directory.standardizedFileURL != base.standardizedFileURL,
              let contents = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        if contents.allSatisfy({ $0 == ".DS_Store" }) {
            try? fm.removeItem(at: directory)
        }
    }
}
