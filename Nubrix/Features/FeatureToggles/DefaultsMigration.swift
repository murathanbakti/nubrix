import Foundation

/// Version 0.3 changed some defaults to suit people who do not write code:
/// developer tabs are off and the song-change preview is on. Installs from
/// before that keep what they had: a value they never changed is written down
/// as the old default, so only new installs get the new defaults.
enum DefaultsMigration {
    static let doneKey = "defaultsMigration.simpleDefaults"

    /// Old defaults, by key, for settings whose default changed.
    static let previousDefaults: [String: Any] = [
        "claudeEnabled": true,
        "devEnabled": true,
        "githubEnabled": true,
        "enableSneakPeek": false,
        // Notifications used to show beside the notch; the drop-down card is new.
        "systemNotificationStyle": "inline",
    ]

    /// `domain` is where the values are stored. Only what was really written
    /// there counts, not defaults the app registered at launch.
    static func run(_ defaults: UserDefaults = .standard, domain: String? = nil) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)
        let stored = defaults.persistentDomain(forName: domain ?? Bundle.main.bundleIdentifier ?? "") ?? [:]
        // `firstLaunch` is written once onboarding has been shown, so its
        // presence means this Mac already ran an older build.
        guard stored["firstLaunch"] != nil else { return }
        for (key, value) in previousDefaults where stored[key] == nil {
            defaults.set(value, forKey: key)
        }
    }
}
