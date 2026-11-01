import AppKit
import Combine
import EventKit
import SwiftUI

struct TodayTileEvent: Equatable {
    let title: String
    let start: Date
    let isAllDay: Bool
    let color: Color
    let isTomorrow: Bool
}

enum TodayTileAccess: Equatable {
    case granted
    case needsAccess
}

enum TodayTileFormat {
    static func monthYear(_ date: Date, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted).month(.wide).year()
        style.locale = locale
        return date.formatted(style)
    }

    static func time(_ date: Date, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.locale = locale
        return date.formatted(style)
    }

    static func tomorrowWord(locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return formatter.string(from: tomorrow)
    }
}

@MainActor
final class TodayTileModel: ObservableObject {
    static let shared = TodayTileModel()

    @Published private(set) var access: TodayTileAccess = .needsAccess
    @Published private(set) var events: [EventModel] = []

    private let service = CalendarService.shared
    private var cancellables = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?
    private var dirty = true
    private var loadedDay: Date?
    private var isVisible = false

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible { refresh() }
    }

    private init() {
        SharedEventStore.shared.changes
            .sink { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.dirty = true
                    if self.isVisible { self.refresh() }
                }
            }
            .store(in: &cancellables)
        CalendarManager.shared.$selectedCalendarIDs
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.dirty = true
                if self.isVisible { self.refresh() }
            }
            .store(in: &cancellables)
    }

    func refresh() {
        let granted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        let current: TodayTileAccess = granted ? .granted : .needsAccess
        if access != current {
            access = current
            dirty = true
        }
        guard granted else {
            loadTask?.cancel()
            if !events.isEmpty { events = [] }
            return
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard dirty || loadedDay != start else { return }
        dirty = false
        loadedDay = start
        loadTask?.cancel()
        let end = calendar.date(byAdding: .day, value: 2, to: start) ?? start
        let ids = Array(CalendarManager.shared.selectedCalendarIDs)
        loadTask = Task { [service] in
            let result = await service.events(from: start, to: end, calendars: ids)
            guard !Task.isCancelled else { return }
            if self.events != result { self.events = result }
        }
    }

    func requestAccess() {
        Task {
            await CalendarManager.shared.checkCalendarAuthorization()
            refresh()
            if EKEventStore.authorizationStatus(for: .event) != .fullAccess,
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
            {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func nextEvent(now: Date = Date()) -> TodayTileEvent? {
        let calendar = Calendar.current
        let candidates = events
            .filter { !$0.type.isReminder }
            .sorted { $0.start < $1.start }
        let today = candidates.filter { calendar.isDate($0.start, inSameDayAs: now) || ($0.start < now && $0.end > now) }
        if let timed = today.first(where: { !$0.isAllDay && $0.end > now }) {
            return Self.tile(timed, tomorrow: false)
        }
        if let allDay = today.first(where: { $0.isAllDay }) {
            return Self.tile(allDay, tomorrow: false)
        }
        if let next = candidates.first(where: { calendar.isDateInTomorrow($0.start) }) {
            return Self.tile(next, tomorrow: true)
        }
        return nil
    }

    func dotEvent(now: Date = Date()) -> TodayTileEvent? {
        let horizon = now.addingTimeInterval(3600)
        let match = events
            .filter { !$0.type.isReminder && !$0.isAllDay && $0.end > now && $0.start <= horizon }
            .min { $0.start < $1.start }
        return match.map { Self.tile($0, tomorrow: false) }
    }

    private static func tile(_ event: EventModel, tomorrow: Bool) -> TodayTileEvent {
        TodayTileEvent(
            title: event.title, start: event.start, isAllDay: event.isAllDay,
            color: Color(nsColor: event.calendar.color), isTomorrow: tomorrow)
    }
}
