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
            Text((calendarOn ? "" : "Turn on Calendar in Settings to use the countdown. ") + "Counts down to the next meeting in the closed notch. The meeting card on the Home tab has a Join button when the event has a Zoom, Google Meet, Teams, Webex, Whereby or Slack Huddle link.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private var leadBinding: Binding<Int> {
        Binding(
            get: { MeetingLeadOption.normalized(lead) },
            set: { lead = $0 })
    }
}
