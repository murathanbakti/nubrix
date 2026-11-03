import Defaults
import SwiftUI

struct CalendarSettings: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) var showCalendar

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showCalendar) {
                    Text("Enable calendar")
                }
            } footer: {
                SettingsFooter("Shows your events in the notch and counts down to meetings. When off, Nubrix does not read your calendars.")
            }

            Group {
                calendarsSection
                MeetingSettingsSection()
            }
            .disabled(!showCalendar)
        }
        .settingsPage(.calendar)
        .task {
            await calendarManager.refreshAuthorizationStatus()
        }
    }

    private var calendarsSection: some View {
        Section {
            switch calendarManager.calendarAuthorizationStatus {
            case .fullAccess:
                ForEach(calendarManager.eventCalendars, id: \.id) { calendar in
                    Toggle(
                        isOn: Binding(
                            get: { calendarManager.getCalendarSelected(calendar) },
                            set: { isSelected in
                                Task {
                                    await calendarManager.setCalendarSelected(
                                        calendar, isSelected: isSelected)
                                }
                            }
                        )
                    ) {
                        Text(calendar.title)
                    }
                    .tint(lighterColor(from: calendar.color))
                }
            case .notDetermined:
                HStack {
                    Text("Calendar access is needed.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Allow access…") {
                        Task { await calendarManager.checkCalendarAuthorization() }
                    }
                }
            default:
                HStack {
                    Label("Calendar access is off", systemImage: "lock.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Open System Settings") {
                        Permissions.client.openSystemSettings(.calendar)
                    }
                }
            }
        } header: {
            Text("Calendars")
        } footer: {
            SettingsFooter("Nubrix asks for calendar access only to show and add your events. They stay on your Mac.")
        }
    }
}
