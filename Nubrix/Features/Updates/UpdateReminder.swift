import Foundation

struct UpdateReminder: Equatable, Sendable {
    let version: String
    let readyToInstall: Bool
}

enum UpdateReminderEvent: Equatable, Sendable {
    case willShow(handledBySparkle: Bool, userInitiated: Bool, version: String, readyToInstall: Bool)
    case attention
    case sessionFinished
}

enum UpdateReminderLogic {
    static func reduce(_ current: UpdateReminder?, _ event: UpdateReminderEvent) -> UpdateReminder? {
        switch event {
        case .willShow(let handledBySparkle, let userInitiated, let version, let readyToInstall):
            guard !handledBySparkle, !userInitiated else { return current }
            return UpdateReminder(version: version, readyToInstall: readyToInstall)
        case .attention, .sessionFinished:
            return nil
        }
    }
}
