import Defaults

extension Defaults.Keys {
    static let systemNotificationsEnabled = Key<Bool>("systemNotificationsEnabled", default: false)
    static let systemNotificationApps = Key<[String]>("systemNotificationApps", default: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"])
    static let systemNotificationsShowBody = Key<Bool>("systemNotificationsShowBody", default: true)
    static let systemNotificationsSkipFrontmost = Key<Bool>("systemNotificationsSkipFrontmost", default: true)
    static let systemNotificationQuickReply = Key<Bool>("systemNotificationQuickReply", default: true)
    static let quickReplyPreviewsHidden = Key<[String: String]>("quickReplyPreviewsHidden", default: [:])
}
