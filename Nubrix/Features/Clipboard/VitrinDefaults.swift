import Foundation
import Defaults
import KeyboardShortcuts

extension Defaults.Keys {
    static let vitrinEnabled = Key<Bool>("vitrinEnabled", default: true)
    static let vitrinCaptureImages = Key<Bool>("vitrinCaptureImages", default: true)
    static let vitrinCaptureText = Key<Bool>("vitrinCaptureText", default: true)
    static let vitrinCaptureLinks = Key<Bool>("vitrinCaptureLinks", default: true)
    static let vitrinCaptureScreenshots = Key<Bool>("vitrinCaptureScreenshots", default: true)
    static let vitrinScreenshotPreview = Key<Bool>("vitrinScreenshotPreview", default: true)
    static let vitrinScreenshotFolderBookmark = Key<Data?>("vitrinScreenshotFolderBookmark", default: nil)
    static let vitrinScreenshotBookmarkReadOnly = Key<Bool>("vitrinScreenshotBookmarkReadOnly", default: false)
    static let vitrinScreenshotPromptDismissed = Key<Bool>("vitrinScreenshotPromptDismissed", default: false)
    static let vitrinRetentionDays = Key<Int>("vitrinRetentionDays", default: 30)
    static let vitrinExcludedApps = Key<[String]>("vitrinExcludedApps", default: VitrinDefaultsValues.excludedApps)
    static let vitrinHideFromCapture = Key<Bool>("vitrinHideFromCapture", default: true)
}

enum VitrinDefaultsValues {
    static let excludedApps = [
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.markmcguill.strongbox",
        "me.proton.pass.electron",
        "in.sinew.Enpass-Desktop"
    ]
}

extension KeyboardShortcuts.Name {
    static let toggleVitrin = Self("toggleVitrin", default: .init(.v, modifiers: [.control, .option]))
}
