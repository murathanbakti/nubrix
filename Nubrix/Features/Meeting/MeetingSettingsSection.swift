import Defaults
import SwiftUI

struct MeetingSettingsSection: View {
    @Default(.showCalendar) private var calendarOn
    @Default(.meetingCountdownEnabled) private var countdownOn
    @Default(.meetingLeadMinutes) private var lead

    private var enabled: Bool { calendarOn && countdownOn }

    var body: some View {
        Section {
            Defaults.Toggle(key: .meetingCountdownEnabled) {
                Text("Meeting countdown")
            }
            .disabled(!calendarOn)
            Picker("Start countdown", selection: leadBinding) {
                ForEach(MeetingLeadOption.minutes, id: \.self) { minutes in
                    Text("\(minutes) min before").tag(minutes)
                }
            }
            .disabled(!enabled)
            Defaults.Toggle(key: .meetingBannerAtOneMinute) {
                Text("Show banner at 1 minute")
            }
            .disabled(!enabled)
        } header: {
            Text("Meetings")
        } footer: {
            SettingsFooter("Counts down to the next meeting in the closed notch. The Home tab shows a Join button for Zoom, Google Meet, Teams, Webex, Whereby and Slack Huddle links.")
        }
    }

    private var leadBinding: Binding<Int> {
        Binding(
            get: { MeetingLeadOption.normalized(lead) },
            set: { lead = $0 })
    }
}
