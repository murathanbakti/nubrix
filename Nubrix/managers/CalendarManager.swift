//
//  CalendarManager.swift
//  Nubrix
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import Combine
import Defaults
import EventKit
import SwiftUI

// MARK: - CalendarManager

@MainActor
class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    @Published var currentWeekStartDate: Date
    @Published var events: [EventModel] = []
    @Published var allCalendars: [CalendarModel] = []
    @Published var eventCalendars: [CalendarModel] = []
    @Published var selectedCalendarIDs: Set<String> = []
    @Published var calendarAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    private var selectedCalendars: [CalendarModel] = []
    private let calendarService = CalendarService.shared
    private var storeChanges: AnyCancellable?
    private var settingObserver: AnyCancellable?

    private init() {
        self.currentWeekStartDate = CalendarManager.startOfDay(Date())
        calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
        settingObserver = Defaults.publisher(.showCalendar)
            .map(\.newValue)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                MainActor.assumeIsolated { self?.setActive(enabled) }
            }
    }

    private func setActive(_ enabled: Bool) {
        if enabled {
            setupEventStoreChangedObserver()
            Task { await reloadCalendarLists() }
        } else {
            storeChanges = nil
            events = []
            allCalendars = []
            eventCalendars = []
        }
    }

    private func setupEventStoreChangedObserver() {
        guard storeChanges == nil else { return }
        storeChanges = SharedEventStore.shared.changes.sink { [weak self] in
            Task { @MainActor in
                await self?.reloadCalendarLists()
            }
        }
    }

    @MainActor
    func reloadCalendarLists() async {
        guard Defaults[.showCalendar] else { return }
        let all = await calendarService.calendars()
        if eventCalendars != all { eventCalendars = all }
        if allCalendars != all { allCalendars = all }
        updateSelectedCalendars()
    }

    func refreshAuthorizationStatus() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        calendarAuthorizationStatus = status
        if status == .fullAccess, Defaults[.showCalendar] {
            await reloadCalendarLists()
            await updateEvents()
        }
    }

    func checkCalendarAuthorization() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        DispatchQueue.main.async {
            print("📅 Current calendar authorization status: \(status)")
            self.calendarAuthorizationStatus = status
        }

        switch status {
        case .notDetermined:
            guard let granted = try? await calendarService.requestAccess(to: .event) else {
                self.calendarAuthorizationStatus = .notDetermined
                return
            }
            self.calendarAuthorizationStatus = granted ? .fullAccess : .denied
            if granted {
                MeetingWatcher.shared.refresh()
                await reloadCalendarLists()
                events = await calendarService.events(
                    from: currentWeekStartDate,
                    to: Calendar.current.date(byAdding: .day, value: 1, to: currentWeekStartDate)!,
                    calendars: selectedCalendars.map { $0.id })
            }
        case .restricted, .denied:
            NSLog("Calendar access denied or restricted")
        case .fullAccess:
            NSLog("Full access")
            await reloadCalendarLists()
            events = await calendarService.events(
                from: currentWeekStartDate,
                to: Calendar.current.date(byAdding: .day, value: 1, to: currentWeekStartDate)!,
                calendars: selectedCalendars.map { $0.id })
        case .writeOnly:
            NSLog("Write only")
        @unknown default:
            print("Unknown authorization status")
        }
    }
    
    func updateSelectedCalendars() {
        // Populate selectedCalendarIDs based on Defaults calendar selection state
        let ids: Set<String>
        switch Defaults[.calendarSelectionState] {
        case .all:
            ids = Set(allCalendars.map { $0.id })
        case .selected(let identifiers):
            ids = identifiers
        }
        if selectedCalendarIDs != ids { selectedCalendarIDs = ids }
        selectedCalendars = allCalendars.filter { selectedCalendarIDs.contains($0.id) }
    }

    func getCalendarSelected(_ calendar: CalendarModel) -> Bool {
        return selectedCalendarIDs.contains(calendar.id)
    }

    func setCalendarSelected(_ calendar: CalendarModel, isSelected: Bool) async {
        var selectionState = Defaults[.calendarSelectionState]

        switch selectionState {
        case .all:
            if !isSelected {
                let identifiers = Set(allCalendars.map { $0.id }).subtracting([calendar.id])
                selectionState = .selected(identifiers)
            }

        case .selected(var identifiers):
            if isSelected {
                identifiers.insert(calendar.id)
            } else {
                identifiers.remove(calendar.id)
            }

            selectionState =
                identifiers.isEmpty
                ? .all : identifiers.count == allCalendars.count ? .all : .selected(identifiers)  // if empty, select all
        }

        Defaults[.calendarSelectionState] = selectionState
        updateSelectedCalendars()
        await updateEvents()
    }

    static func startOfDay(_ date: Date) -> Date {
        return Calendar.current.startOfDay(for: date)
    }

    func updateCurrentDate(_ date: Date) async {
        currentWeekStartDate = Calendar.current.startOfDay(for: date)
        await updateEvents()
    }

    private func updateEvents() async {
        let calendarIDs = selectedCalendars.map { $0.id }
        let eventsResult = await calendarService.events(
            from: currentWeekStartDate,
            to: Calendar.current.date(byAdding: .day, value: 1, to: currentWeekStartDate)!,
            calendars: calendarIDs
        )
        self.events = eventsResult
    }
}
