import AppKit
import SwiftUI

extension NubrixCalendarView {
    var rightColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                goToField
                NubrixCalendarPill(symbol: "xmark") { onClose() }
                    .help(text.close)
            }
            if case .found(let date) = outcome {
                resultChip(date)
            } else if case .failed(let message) = outcome {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(NubrixCalendarMetrics.red.opacity(0.95))
                    .padding(.horizontal, 4)
            }
            dayHeader
            if store.access != .granted {
                accessPanel
            } else if showForm {
                NubrixEventForm(
                    store: store,
                    day: selected,
                    fmt: fmt,
                    seedTitle: formSeed,
                    onSaved: { title in
                        showForm = false
                        focus = .grid
                        showToast("\(text.added): \(title)")
                    },
                    onCancel: closeForm)
            } else {
                eventList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            if let toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Color(white: 0.16), in: Capsule())
                    .overlay(Capsule().strokeBorder(NubrixCalendarMetrics.stroke, lineWidth: 1))
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: toast)
    }

    var goToField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NubrixCalendarMetrics.meta)
            TextField(text.goToPlaceholder, text: $gotoText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focus, equals: .goTo)
                .onSubmit(submitGoTo)
            if !gotoText.isEmpty {
                Button {
                    gotoText = ""
                    outcome = .none
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(NubrixCalendarMetrics.meta)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(NubrixCalendarMetrics.fill, in: RoundedRectangle(cornerRadius: NubrixCalendarMetrics.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NubrixCalendarMetrics.radius, style: .continuous)
                .strokeBorder(focus == .goTo ? Color.white.opacity(0.3) : NubrixCalendarMetrics.stroke, lineWidth: 1))
    }

    func resultChip(_ date: Date) -> some View {
        let parts = [fmt.dayMonthYear(date), fmt.weekday(date), fmt.relativeDays(from: Date(), to: date)]
        return HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 11, weight: .semibold))
            Text(parts.joined(separator: " · "))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .fixedSize()
        .background(NubrixCalendarMetrics.red.opacity(0.28), in: Capsule())
        .overlay(Capsule().strokeBorder(NubrixCalendarMetrics.red.opacity(0.5), lineWidth: 1))
    }

    var dayHeader: some View {
        let events = store.events(on: selected)
        let subtitle = [fmt.capitalized(fmt.relativeDays(from: Date(), to: selected)), text.eventCount(events.count)]
        return HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(fmt.longDate(selected))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(subtitle.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(NubrixCalendarMetrics.meta)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            NubrixCalendarPill(symbol: "arrow.up.forward.app") { openCalendarApp() }
                .help(text.openCalendar)
            Button { openForm() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                    Text(text.newEvent).font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(NubrixCalendarMetrics.red.opacity(store.access == .granted ? 0.9 : 0.35), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(store.access != .granted || showForm)
            .opacity(showForm ? 0.4 : 1)
            .help("\(text.newEvent) (⌘N)")
        }
    }

    @ViewBuilder
    var eventList: some View {
        let events = store.events(on: selected)
        if events.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.3))
                Text(text.noEvents)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                Text(text.noEventsHint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(events) { event in
                        NubrixEventRow(
                            event: event,
                            timeLabel: fmt.timeRange(for: event, on: selected),
                            dimmed: event.end < Date() && !event.isAllDay
                        ) { open(event) }
                    }
                }
                .padding(.bottom, 2)
            }
            .scrollIndicators(.never)
        }
    }

    var accessPanel: some View {
        VStack(spacing: 8) {
            Image(systemName: store.access == .denied ? "calendar.badge.exclamationmark" : "calendar.badge.plus")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.white.opacity(0.4))
            Text(text.accessTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(store.access == .denied ? text.deniedBody : text.accessBody)
                .font(.system(size: 11))
                .foregroundStyle(NubrixCalendarMetrics.meta)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if store.access == .denied {
                NubrixCalendarPill(title: text.openSettings) { openPrivacySettings() }
            } else {
                NubrixCalendarPill(title: text.allowAccess) { Task { await store.requestAccess() } }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func open(_ event: NubrixCalendarEvent) {
        if let url = event.openURL, NSWorkspace.shared.open(url) { return }
        openCalendarApp()
    }

    func openCalendarApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct NubrixEventRow: View {
    let event: NubrixCalendarEvent
    let timeLabel: String
    let dimmed: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color(nsColor: event.color))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(timeLabel)
                        if let location = event.location {
                            Text("·")
                            Text(location).lineLimit(1)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(NubrixCalendarMetrics.meta)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? NubrixCalendarMetrics.fillHover : NubrixCalendarMetrics.fill, in: RoundedRectangle(cornerRadius: NubrixCalendarMetrics.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NubrixCalendarMetrics.radius, style: .continuous).strokeBorder(NubrixCalendarMetrics.stroke, lineWidth: 1))
            .opacity(dimmed ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct NubrixEventForm: View {
    @ObservedObject var store: NubrixCalendarStore
    let day: Date
    let fmt: NubrixCalendarFormat
    let seedTitle: String
    let onSaved: (String) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var isAllDay = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var duration: Int? = 60
    @State private var calendarID = ""
    @State private var location = ""
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case title, location }

    private var text: NubrixCalendarText { fmt.text }
    private var selectedCalendar: NubrixCalendarInfo? { store.writableCalendars.first { $0.id == calendarID } }
    private var effectiveEnd: Date {
        if let duration { return start.addingTimeInterval(TimeInterval(duration * 60)) }
        return end
    }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && selectedCalendar != nil && (isAllDay || effectiveEnd > start)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            field {
                TextField(text.titlePlaceholder, text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .focused($focus, equals: .title)
                    .onSubmit(save)
            }
            HStack(spacing: 8) {
                Toggle(text.allDay, isOn: $isAllDay)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11.5))
                Spacer(minLength: 0)
                if !isAllDay {
                    Text(text.start).font(.system(size: 11)).foregroundStyle(NubrixCalendarMetrics.meta)
                    DatePicker("", selection: $start, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field)
                        .labelsHidden()
                        .fixedSize()
                }
            }
            .frame(height: 24)
            if !isAllDay {
                HStack(spacing: 5) {
                    ForEach([15, 30, 60, 120], id: \.self) { minutes in
                        durationChip(text.duration(minutes), active: duration == minutes) { duration = minutes }
                    }
                    durationChip(text.custom, active: duration == nil) {
                        end = start.addingTimeInterval(3600)
                        duration = nil
                    }
                    if duration == nil {
                        DatePicker("", selection: $end, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.field)
                            .labelsHidden()
                            .fixedSize()
                    }
                    Spacer(minLength: 0)
                }
            }
            calendarMenu
            field {
                TextField(text.locationPlaceholder, text: $location)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($focus, equals: .location)
                    .onSubmit(save)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(NubrixCalendarMetrics.red)
            } else if !isAllDay && duration == nil && effectiveEnd <= start {
                Text(text.endBeforeStart)
                    .font(.system(size: 11))
                    .foregroundStyle(NubrixCalendarMetrics.red)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                NubrixCalendarPill(title: "\(text.cancel)  esc", action: onCancel)
                Button(action: save) {
                    Text("\(text.save)  ↩")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 22)
                        .background(NubrixCalendarMetrics.red.opacity(canSave ? 0.9 : 0.35), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear(perform: setup)
    }

    private func setup() {
        title = seedTitle
        start = NubrixEventDraft.defaultStart(day: day, now: Date(), calendar: fmt.calendar)
        end = start.addingTimeInterval(3600)
        calendarID = store.defaultCalendarID ?? store.writableCalendars.first?.id ?? ""
        focus = .title
    }

    private func save() {
        guard canSave else { return }
        let draft = NubrixEventDraft(
            title: title, isAllDay: isAllDay, start: start, end: effectiveEnd,
            calendarID: calendarID, location: location)
        do {
            try store.save(draft)
            onSaved(title.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            errorMessage = "\(text.saveFailed): \(error.localizedDescription)"
        }
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(NubrixCalendarMetrics.fill, in: RoundedRectangle(cornerRadius: NubrixCalendarMetrics.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NubrixCalendarMetrics.radius, style: .continuous).strokeBorder(NubrixCalendarMetrics.stroke, lineWidth: 1))
    }

    private func durationChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(active ? NubrixCalendarMetrics.red.opacity(0.75) : Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var calendarMenu: some View {
        Menu {
            ForEach(store.writableCalendars) { info in
                Button {
                    calendarID = info.id
                } label: {
                    Text(info.account.isEmpty ? info.title : "\(info.title) — \(info.account)")
                }
            }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color(nsColor: selectedCalendar?.color ?? .systemBlue))
                    .frame(width: 8, height: 8)
                Text(selectedCalendar?.title ?? text.noWritableCalendar)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(NubrixCalendarMetrics.meta)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(NubrixCalendarMetrics.fill, in: RoundedRectangle(cornerRadius: NubrixCalendarMetrics.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NubrixCalendarMetrics.radius, style: .continuous).strokeBorder(NubrixCalendarMetrics.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}
