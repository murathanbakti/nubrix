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

    private let service = CalendarService()
    private var storeObserver: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?

    private init() {
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        if let storeObserver { NotificationCenter.default.removeObserver(storeObserver) }
    }

    func refresh() {
        let status = EKEventStore.authorizationStatus(for: .event)
        let granted = status == .fullAccess
        access = granted ? .granted : .needsAccess
        guard granted else {
            events = []
            return
        }
        loadTask?.cancel()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 2, to: start) ?? start
        let ids = Array(CalendarManager.shared.selectedCalendarIDs)
        loadTask = Task { [service] in
            let result = await service.events(from: start, to: end, calendars: ids)
            guard !Task.isCancelled else { return }
            self.events = result
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
