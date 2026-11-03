import Foundation
import Defaults

extension Defaults.Keys {
    static let updateAutoCheck = Key<Bool?>("updateAutoCheck", default: nil)
    static let updateLastCheck = Key<Date?>("updateLastCheck", default: nil)
    static let updateLatestVersion = Key<String?>("updateLatestVersion", default: nil)
    static let updateSkippedVersion = Key<String?>("updateSkippedVersion", default: nil)
}
