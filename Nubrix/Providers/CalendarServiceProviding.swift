//
//  CalendarServiceProvider.swift
//  Calendr
//
//  Created by Paker on 31/12/20.
//  Original source: Original source: https://github.com/pakerwreah/Calendr
//  Modified by Alexander on 08/06/25
//

import Foundation
@preconcurrency import EventKit

protocol CalendarServiceProviding {
    func requestAccess(to type: EKEntityType) async throws -> Bool
    func calendars() async -> [CalendarModel]
    func events(from start: Date, to end: Date, calendars: [String]) async -> [EventModel]
}

final class CalendarService: CalendarServiceProviding, @unchecked Sendable {
    static let shared = CalendarService()

    private let eventStore: SharedEventStore

    init(eventStore: SharedEventStore = .shared) {
        self.eventStore = eventStore
    }

    @MainActor
    func requestAccess(to type: EKEntityType) async throws -> Bool {
        switch type {
        case .event:
            return try await eventStore.store.requestFullAccessToEvents()
        case .reminder:
            return try await eventStore.store.requestFullAccessToReminders()
        @unknown default:
            return false
        }
    }

    private func hasAccess(to entityType: EKEntityType) -> Bool {
        EKEventStore.authorizationStatus(for: entityType) == .fullAccess
    }

    func calendars() async -> [CalendarModel] {
        let types = [EKEntityType.event, .reminder].filter { hasAccess(to: $0) }
        guard !types.isEmpty else { return [] }
        return await eventStore.perform { store in
            types.flatMap { store.calendars(for: $0) }.map { CalendarModel(from: $0) }
        }
    }

    func events(from start: Date, to end: Date, calendars ids: [String]) async -> [EventModel] {
        let wantsEvents = hasAccess(to: .event)
        let wantsReminders = hasAccess(to: .reminder)
        guard wantsEvents || wantsReminders else { return [] }

        let fetched: (events: [EventModel], reminderCalendars: [EKCalendar]) = await eventStore.perform { store in
            var models: [EventModel] = []
            if wantsEvents {
                let calendars = store.calendars(for: .event).filter { ids.isEmpty || ids.contains($0.calendarIdentifier) }
                let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
                models = store.events(matching: predicate).compactMap { EventModel(from: $0) }
            }
            let reminderCalendars = wantsReminders
                ? store.calendars(for: .reminder).filter { ids.isEmpty || ids.contains($0.calendarIdentifier) }
                : []
            return (models, reminderCalendars)
        }

        var events = fetched.events
        if wantsReminders {
            events.append(contentsOf: await fetchReminders(from: start, to: end, calendars: fetched.reminderCalendars))
        }
        return events.sorted { $0.start < $1.start }
    }

    private func fetchReminders(from start: Date, to end: Date, calendars: [EKCalendar]) async -> [EventModel] {
        let boxed = EventKitBox(value: calendars)
        return await withCheckedContinuation { continuation in
            eventStore.queue.async {
                let store = self.eventStore.store
                let predicate = store.predicateForReminders(in: boxed.value)
                store.fetchReminders(matching: predicate) { reminders in
                    let models = (reminders ?? []).compactMap { reminder -> EventModel? in
                        guard let dueDate = reminder.dueDateComponents?.date, dueDate >= start, dueDate <= end else { return nil }
                        return EventModel(from: reminder)
                    }
                    continuation.resume(returning: models)
                }
            }
        }
    }

    func setReminderCompleted(reminderID: String, completed: Bool) async {
        await eventStore.perform { store in
            guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else { return }
            reminder.isCompleted = completed
            do {
                try store.save(reminder, commit: true)
            } catch {
                print("Failed to update reminder completion: \(error)")
            }
        }
    }
}

// MARK: - Model Extensions

extension CalendarModel {
    init(from calendar: EKCalendar) {
        self.init(
            id: calendar.calendarIdentifier,
            account: calendar.accountTitle,
            title: calendar.title,
            color: calendar.color,
            isSubscribed: calendar.isSubscribed || calendar.isDelegate,
            isReminder: calendar.allowedEntityTypes.contains(.reminder)
        )
    }
}

extension EventModel {
    init?(from event: EKEvent) {
        guard let calendar = event.calendar else { return nil }
        
        self.init(
            id: event.calendarItemIdentifier,
            start: event.startDate,
            end: event.endDate,
            title: event.title ?? "",
            location: event.location,
            notes: event.notes,
            url: event.url,
            isAllDay: event.shouldBeAllDay,
            type: .init(from: event),
            calendar: .init(from: calendar),
            participants: .init(from: event),
            timeZone: calendar.isSubscribed || calendar.isDelegate ? nil : event.timeZone,
            hasRecurrenceRules: event.hasRecurrenceRules || event.isDetached,
            priority: nil
        )
    }
    
    init?(from reminder: EKReminder) {
        guard let calendar = reminder.calendar,
              let dueDateComponents = reminder.dueDateComponents,
              let date = Calendar.current.date(from: dueDateComponents)
        else { return nil }
        
        self.init(
            id: reminder.calendarItemIdentifier,
            start: date,
            end: Calendar.current.endOfDay(for: date),
            title: reminder.title ?? "",
            location: reminder.location,
            notes: reminder.notes,
            url: reminder.url,
            isAllDay: dueDateComponents.hour == nil,
            type: .reminder(completed: reminder.isCompleted),
            calendar: .init(from: calendar),
            participants: [],
            timeZone: calendar.isSubscribed || calendar.isDelegate ? nil : reminder.timeZone,
            hasRecurrenceRules: reminder.hasRecurrenceRules,
            priority: .init(from: reminder.priority)
        )
    }
}

extension EventType {
    init(from event: EKEvent) {
        self = event.birthdayContactIdentifier != nil ? .birthday : .event(.init(from: event.currentUser?.participantStatus))
    }
}

extension AttendanceStatus {
    init(from status: EKParticipantStatus?) {
        switch status {
        case .accepted:
            self = .accepted
        case .tentative:
            self = .maybe
        case .declined:
            self = .declined
        case .pending:
            self = .pending
        default:
            self = .unknown
        }
    }
}

extension Array where Element == Participant {
    init(from event: EKEvent) {
        var participants = event.attendees ?? []
        if let organizer = event.organizer, !participants.contains(where: { $0.url == organizer.url }) {
            participants.append(organizer)
        }
        self.init(
            participants.map { .init(from: $0, isOrganizer: $0.url == event.organizer?.url) }
        )
    }
}

extension Participant {
    init(from participant: EKParticipant, isOrganizer: Bool) {
        self.init(
            name: participant.name ?? participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: ""),
            status: .init(from: participant.participantStatus),
            isOrganizer: isOrganizer,
            isCurrentUser: participant.isCurrentUser
        )
    }
}

extension Priority {
    init?(from p: Int) {
        switch p {
        case 1...4:
            self = .high
        case 5:
            self = .medium
        case 6...9:
            self = .low
        default:
            return nil
        }
    }
}

// MARK: - Helper Extensions

private extension EKCalendar {
    var accountTitle: String {
        switch source.sourceType {
        case .local, .subscribed, .birthdays:
            return "Other"
        default:
            return source.title
        }
    }
    
    var isDelegate: Bool {
        if #available(macOS 13.0, *) {
            return source.isDelegate
        } else {
            return false
        }
    }
}

private extension EKEvent {
    var currentUser: EKParticipant? {
        attendees?.first(where: \.isCurrentUser)
    }
    
    var shouldBeAllDay: Bool {
        guard !isAllDay else { return true }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: startDate)
        let endOfDay = calendar.dateInterval(of: .day, for: endDate)?.end
        return startDate == startOfDay && endDate == endOfDay
    }
}

private extension Calendar {
    func endOfDay(for date: Date) -> Date {
        dateInterval(of: .day, for: date)?.end ?? date
    }
}
