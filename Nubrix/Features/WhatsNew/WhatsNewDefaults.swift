import Defaults

extension Defaults.Keys {
    /// Marketing version for which the What's New window was last handled (shown or skipped).
    static let lastSeenWhatsNewVersion = Key<String?>("lastSeenWhatsNewVersion", default: nil)
}
