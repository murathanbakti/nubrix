import Defaults

extension Defaults.Keys {
    static let systemNotificationsEnabled = Key<Bool>("systemNotificationsEnabled", default: false)
    static let systemNotificationApps = Key<[String]>("systemNotificationApps", default: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"])
    static let systemNotificationsShowBody = Key<Bool>("systemNotificationsShowBody", default: true)
    static let systemNotificationsSkipFrontmost = Key<Bool>("systemNotificationsSkipFrontmost", default: true)
}

/// How a notification from another app shows up in the notch.
enum SystemNotificationStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case dropDown
    case inline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dropDown: return "Drops down, like iPhone"
        case .inline: return "Beside the notch"
        }
    }
}

extension Defaults.Keys {
    static let systemNotificationStyle = Key<SystemNotificationStyle>("systemNotificationStyle", default: .dropDown)
}

/// How the Notifications tab bundles notifications together.
enum SystemNotificationGrouping: String, CaseIterable, Identifiable, Defaults.Serializable {
    case conversation
    case app
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conversation: return "By conversation"
        case .app: return "By app"
        case .off: return "Off"
        }
    }
}

extension Defaults.Keys {
    static let systemNotificationGrouping = Key<SystemNotificationGrouping>("systemNotificationGrouping", default: .conversation)
    static let systemNotificationsCollapseGroups = Key<Bool>("systemNotificationsCollapseGroups", default: true)
    static let systemNotificationsShowBanner = Key<Bool>("systemNotificationsShowBanner", default: true)
}
