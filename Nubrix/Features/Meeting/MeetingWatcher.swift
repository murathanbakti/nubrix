import AppKit
import Combine
import Defaults
import EventKit
import SwiftUI

@MainActor
final class MeetingWatcher: ObservableObject {
    static let shared = MeetingWatcher()

    @Published private(set) var next: MeetingInfo?
    @Published private(set) var banner: MeetingBanner?
    @Published private(set) var now = Date()

    var isCountdownActive: Bool { next != nil }

    private let service = CalendarService()
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var fetchTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var dismissed = Set<String>()
    private var fired: [String: Set<MeetingBannerKind>] = [:]

    private init() {
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        Publishers.Merge3(
            Defaults.publisher(.meetingCountdownEnabled, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.meetingLeadMinutes, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.meetingBannerAtOneMinute, options: []).map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.refresh() }
        .store(in: &cancellables)
        refresh()
    }

    func refresh() {
        fetchTask?.cancel()
        let current = Date()
        guard Defaults[.meetingCountdownEnabled] else {
            clear()
            stopTimer()
            return
        }
        scheduleTimer(after: current)
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            clear()
            return
        }
        let lead = MeetingLeadOption.normalized(Defaults[.meetingLeadMinutes])
        let start = current.addingTimeInterval(-MeetingSelector.ongoingGrace)
        let end = current.addingTimeInterval(TimeInterval(lead * 60 + 120))
        let ids = Array(CalendarManager.shared.selectedCalendarIDs)
        fetchTask = Task { [service] in
            let events = await service.events(from: start, to: end, calendars: ids)
            guard !Task.isCancelled else { return }
            self.apply(events, at: Date(), lead: lead)
        }
    }

    func join() {
        guard let link = next?.link else { return }
        let native = link.nativeURL.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) != nil ? $0 : nil }
        NSWorkspace.shared.open(native ?? link.webURL)
        dismissCurrent()
    }

    func dismissCurrent() {
        if let id = next?.id { dismissed.insert(id) }
        dismissBanner()
        withAnimation(.smooth) { next = nil }
        refresh()
    }

    func dismissBanner() {
        bannerTask?.cancel()
        guard banner != nil else { return }
        withAnimation(.smooth) { banner = nil }
    }

    private func clear() {
        dismissBanner()
        if next != nil { withAnimation(.smooth) { next = nil } }
    }

    private func apply(_ events: [EventModel], at date: Date, lead: Int) {
        now = date
        let candidates = events.compactMap(Self.candidate)
        let picked = MeetingSelector.pick(from: candidates, now: date, leadMinutes: lead, dismissed: dismissed)
        guard let picked, let model = events.first(where: { Self.key($0) == picked.id }) else {
            clear()
            fired.removeAll()
            return
        }
        let info = Self.info(model, id: picked.id)
        if next != info { withAnimation(.smooth) { next = info } }
        fired = fired.filter { $0.key == picked.id }

        let seconds = picked.start.timeIntervalSince(date)
        if let kind = MeetingBannerPlanner.due(
            secondsUntil: seconds, leadMinutes: lead,
            oneMinuteEnabled: Defaults[.meetingBannerAtOneMinute],
            fired: fired[picked.id] ?? []
        ) {
            fired[picked.id, default: []].insert(kind)
            show(MeetingBanner(
                meetingID: picked.id, title: picked.title, start: picked.start,
                minutes: MeetingCountdown.minutes(until: picked.start, now: date), kind: kind))
        }
    }

    private func show(_ next: MeetingBanner) {
        bannerTask?.cancel()
        withAnimation(.smooth) { banner = next }
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.dismissBanner()
        }
    }

    private func scheduleTimer(after date: Date) {
        timer?.invalidate()
        let seconds = date.timeIntervalSinceReferenceDate
        let boundary = (seconds / 60).rounded(.down) * 60 + 60 + 0.2
        let fire = Date(timeIntervalSinceReferenceDate: boundary)
        let timer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private static func key(_ event: EventModel) -> String {
        "\(event.id)@\(Int(event.start.timeIntervalSince1970))"
    }

    private static func candidate(_ event: EventModel) -> MeetingCandidate? {
        guard event.type.isEvent else { return nil }
        let declined = event.participants.first(where: \.isCurrentUser)?.status == .declined
            || event.attendance == .declined
        return MeetingCandidate(
            id: key(event), title: event.title, start: event.start, end: event.end,
            isAllDay: event.isAllDay, isDeclined: declined)
    }

    private static func info(_ event: EventModel, id: String) -> MeetingInfo {
        MeetingInfo(
            id: id, title: event.title, start: event.start, end: event.end,
            color: Color(nsColor: event.calendar.color), calendarTitle: event.calendar.title,
            attendeeCount: event.participants.count,
            link: MeetingLinkDetector.detect(url: event.url, location: event.location, notes: event.notes))
    }
}
