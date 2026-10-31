import SwiftUI

struct MeetingInfo: Equatable, Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let color: Color
    let calendarTitle: String
    let attendeeCount: Int
    let link: MeetingLink?
}

struct MeetingBanner: Equatable {
    let meetingID: String
    let title: String
    let start: Date
    let minutes: Int
    let kind: MeetingBannerKind
}
