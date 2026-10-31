import Defaults

extension Defaults.Keys {
    static let inboxKeepIconInNotch = Key<Bool>("inboxKeepIconInNotch", default: true)
    static let inboxClaudeEnabled = Key<Bool>("inboxClaudeEnabled", default: true)
    static let claudeNotchApprovals = Key<Bool>("claudeNotchApprovals", default: true)
    static let claudeDailyUsage = Key<[String: Double]>("claudeDailyUsage", default: [:])
    static let homeShowClaudeUsage = Key<Bool>("homeShowClaudeUsage", default: true)
    static let inboxNotchctlEnabled = Key<Bool>("inboxNotchctlEnabled", default: true)
}
