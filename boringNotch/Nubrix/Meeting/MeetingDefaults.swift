import Defaults

extension Defaults.Keys {
    static let meetingCountdownEnabled = Key<Bool>("meetingCountdownEnabled", default: true)
    static let meetingLeadMinutes = Key<Int>("meetingLeadMinutes", default: 10)
    static let meetingBannerAtOneMinute = Key<Bool>("meetingBannerAtOneMinute", default: true)
}

enum MeetingLeadOption {
    static let minutes = [5, 10, 15]

    static func normalized(_ value: Int) -> Int {
        minutes.contains(value) ? value : 10
    }
}
