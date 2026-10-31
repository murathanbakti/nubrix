@preconcurrency import EventKit
import AppKit
import Combine
import SwiftUI

enum NubrixCalendarStoreError: LocalizedError {
    case noAccess
    case noCalendar
    case invalidRange

    var errorDescription: String? {
        switch self {
        case .noAccess: return "No calendar access"
        case .noCalendar: return "No writable calendar"
        case .invalidRange: return "End must be after start"
        }
    }
}

@MainActor
final class NubrixCalendarStore: ObservableObject {
    @Published private(set) var access: NubrixCalendarAccess
    @Published private(set) var eventsByDay: [Date: [NubrixCalendarEvent]] = [:]
    @Published private(set) var writableCalendars: [NubrixCalendarInfo] = []
    @Published private(set) var defaultCalendarID: String?

    let calendar: Calendar
    private let eventStore: EKEventStore?
    private var loadedRange: (start: Date, end: Date)?
    private var cancellables = Set<AnyCancellable>()
    private var stubEvents: [NubrixCalendarEvent] = []

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
        let store = EKEventStore()
        self.eventStore = store
        self.access = Self.currentAccess()
        observe(store)
        refreshCalendars()
    }

    init(preview access: NubrixCalendarAccess, calendars: [NubrixCalendarInfo], events: [NubrixCalendarEvent], calendar: Calendar) {
        self.calendar = calendar
        self.eventStore = nil
        self.access = access
        self.writableCalendars = calendars
        self.defaultCalendarID = calendars.first?.id
        self.stubEvents = events
    }

    private static func currentAccess() -> NubrixCalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    private func observe(_ store: EKEventStore) {
        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshAccess() }
            .store(in: &cancellables)
    }

    func refreshAccess() {
        guard eventStore != nil else { return }
        let current = Self.currentAccess()
        if current != access {
            access = current
            reload()
        }
    }

    func requestAccess() async {
        guard let eventStore else { return }
        _ = try? await eventStore.requestFullAccessToEvents()
        access = Self.currentAccess()
        reload()
    }

    func events(on day: Date) -> [NubrixCalendarEvent] {
        eventsByDay[calendar.startOfDay(for: day)] ?? []
    }

    func loadGrid(containing date: Date) {
        let monthStart = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: monthStart) ?? monthStart
        let end = calendar.date(byAdding: .day, value: 42, to: start) ?? start
        loadedRange = (start, end)
        reload()
    }

    private func reload() {
        refreshCalendars()
        guard let range = loadedRange else { return }
        let fetched: [NubrixCalendarEvent]
        if let eventStore {
            guard access == .granted else {
                eventsByDay = [:]
                return
            }
            let predicate = eventStore.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
            fetched = eventStore.events(matching: predicate).map(Self.convert)
        } else {
            fetched = stubEvents
        }
        eventsByDay = bucket(fetched, in: range)
    }

    private func refreshCalendars() {
        guard let eventStore, access == .granted else { return }
        writableCalendars = eventStore.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map { NubrixCalendarInfo(id: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "", color: $0.color ?? .systemBlue) }
        let preferred = eventStore.defaultCalendarForNewEvents?.calendarIdentifier
        defaultCalendarID = writableCalendars.contains { $0.id == preferred } ? preferred : writableCalendars.first?.id
    }

    private static func convert(_ event: EKEvent) -> NubrixCalendarEvent {
        let eventID = event.eventIdentifier ?? ""
        return NubrixCalendarEvent(
            id: "\(eventID)@\(event.startDate.timeIntervalSince1970)",
            eventID: eventID,
            title: (event.title?.isEmpty ?? true) ? "—" : (event.title ?? "—"),
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: (event.location?.isEmpty ?? true) ? nil : event.location,
            color: event.calendar?.color ?? .systemBlue,
            calendarTitle: event.calendar?.title ?? "",
            hasRecurrence: event.hasRecurrenceRules)
    }

    private func bucket(_ events: [NubrixCalendarEvent], in range: (start: Date, end: Date)) -> [Date: [NubrixCalendarEvent]] {
        var result: [Date: [NubrixCalendarEvent]] = [:]
        for event in events {
            var day = calendar.startOfDay(for: max(event.start, range.start))
            var guardCount = 0
            while day < range.end, guardCount < 45 {
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                let overlaps = event.start < next && (event.end > day || (event.end <= event.start && event.start >= day))
                if overlaps { result[day, default: []].append(event) }
                if event.end <= next { break }
                day = next
                guardCount += 1
            }
        }
        for key in result.keys {
            result[key]?.sort {
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                if $0.start != $1.start { return $0.start < $1.start }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
        return result
    }

    func save(_ draft: NubrixEventDraft) throws {
        var start = draft.start
        var end = draft.end
        if draft.isAllDay {
            start = calendar.startOfDay(for: draft.start)
            end = (calendar.date(byAdding: .day, value: 1, to: start) ?? start).addingTimeInterval(-1)
        } else if end <= start {
            throw NubrixCalendarStoreError.invalidRange
        }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let info = writableCalendars.first { $0.id == draft.calendarID }

        guard let eventStore else {
            stubEvents.append(NubrixCalendarEvent(
                id: UUID().uuidString, eventID: "", title: title, start: start, end: end,
                isAllDay: draft.isAllDay, location: location.isEmpty ? nil : location,
                color: info?.color ?? .systemBlue, calendarTitle: info?.title ?? "", hasRecurrence: false))
            reload()
            return
        }
        guard access == .granted else { throw NubrixCalendarStoreError.noAccess }
        guard let ekCalendar = eventStore.calendar(withIdentifier: draft.calendarID) ?? eventStore.defaultCalendarForNewEvents else {
            throw NubrixCalendarStoreError.noCalendar
        }
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.isAllDay = draft.isAllDay
        event.startDate = start
        event.endDate = end
        event.calendar = ekCalendar
        if !location.isEmpty { event.location = location }
        try eventStore.save(event, span: .thisEvent, commit: true)
        reload()
    }
}
