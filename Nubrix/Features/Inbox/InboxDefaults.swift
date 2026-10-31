import Defaults
import Foundation

extension Defaults.Keys {
    static let inboxKeepIconInNotch = Key<Bool>("inboxKeepIconInNotch", default: true)
    static let inboxClaudeEnabled = Key<Bool>("inboxClaudeEnabled", default: true)
    static let claudeNotchApprovals = Key<Bool>("claudeNotchApprovals", default: true)
    static let claudeDailyUsage = Key<[String: Double]>("claudeDailyUsage", default: [:])
    static let homeShowClaudeUsage = Key<Bool>("homeShowClaudeUsage", default: true)
    static let claudePlanUsageEnabled = Key<Bool>("claudePlanUsageEnabled", default: true)
    static let claudePlanUsageCache = Key<Data?>("claudePlanUsageCache", default: nil)
    static let claudePlanAlertKeys = Key<[String]>("claudePlanAlertKeys", default: [])
    static let inboxNotchctlEnabled = Key<Bool>("inboxNotchctlEnabled", default: true)
}
