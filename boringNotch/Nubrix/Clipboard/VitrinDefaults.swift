import Defaults
import KeyboardShortcuts

extension Defaults.Keys {
    static let vitrinEnabled = Key<Bool>("vitrinEnabled", default: true)
    static let vitrinCaptureImages = Key<Bool>("vitrinCaptureImages", default: true)
    static let vitrinCaptureText = Key<Bool>("vitrinCaptureText", default: true)
    static let vitrinCaptureLinks = Key<Bool>("vitrinCaptureLinks", default: true)
    static let vitrinRetentionDays = Key<Int>("vitrinRetentionDays", default: 30)
    static let vitrinExcludedApps = Key<[String]>("vitrinExcludedApps", default: VitrinDefaultsValues.excludedApps)
}

enum VitrinDefaultsValues {
    static let excludedApps = [
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop"
    ]
}

extension KeyboardShortcuts.Name {
    static let toggleVitrin = Self("toggleVitrin", default: .init(.v, modifiers: [.control, .option]))
}
