import Defaults
import SwiftUI

struct MeetingSettingsSection: View {
    @Default(.meetingCountdownEnabled) private var enabled
    @Default(.meetingLeadMinutes) private var lead

    var body: some View {
        Section {
            Defaults.Toggle(key: .meetingCountdownEnabled) {
                Text("Meeting countdown")
            }
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
            Text("Shows the next meeting in the closed notch with a Join button when it has a Zoom, Meet or Teams link.")
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
