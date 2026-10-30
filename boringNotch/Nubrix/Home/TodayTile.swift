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

enum TodayTileMetrics {
    static let width: CGFloat = 126
    static let cornerRadius: CGFloat = 12
    static let fill = Color.white.opacity(0.06)
    static let fillHover = Color.white.opacity(0.10)
    static let stroke = Color.white.opacity(0.08)
    static let secondary = Color.white.opacity(0.6)
}

enum TodayTileFormat {
    static func weekday(_ date: Date, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted).weekday(.abbreviated)
        style.locale = locale
        return date.formatted(style).uppercased(with: locale)
    }

    static func day(_ date: Date) -> String {
        String(Calendar.current.component(.day, from: date))
    }

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

struct TodayTileView: View {
    let date: Date
    let event: TodayTileEvent?
    let access: TodayTileAccess
    var locale: Locale = .autoupdatingCurrent
    var onTap: () -> Void = {}
    var onRequestAccess: () -> Void = {}

    @State private var hovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TodayTileMetrics.cornerRadius, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(TodayTileFormat.weekday(date, locale: locale))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.red)
                .lineLimit(1)
            Text(TodayTileFormat.day(date))
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, -1)
            Text(TodayTileFormat.monthYear(date, locale: locale))
                .font(.system(size: 11))
                .foregroundStyle(TodayTileMetrics.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 6)
            footer
        }
        .frame(width: TodayTileMetrics.width - 24, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(hovering ? TodayTileMetrics.fillHover : TodayTileMetrics.fill)
        .clipShape(shape)
        .overlay(shape.strokeBorder(TodayTileMetrics.stroke, lineWidth: 1))
        .contentShape(shape)
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.snappy(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var footer: some View {
        switch access {
        case .needsAccess:
            Button(action: onRequestAccess) {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8.5, weight: .semibold))
                    Text("Allow calendar access")
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
        case .granted:
            if let event {
                eventFooter(event)
            } else {
                Text("No events")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
    }

    private func eventFooter(_ event: TodayTileEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle()
                    .fill(event.color)
                    .frame(width: 6, height: 6)
                Text(timeLabel(event))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(TodayTileMetrics.secondary)
                    .lineLimit(1)
            }
            Text(event.title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func timeLabel(_ event: TodayTileEvent) -> String {
        let base = event.isAllDay ? "All-day" : TodayTileFormat.time(event.start, locale: locale)
        if event.isTomorrow {
            return "\(TodayTileFormat.tomorrowWord(locale: locale)) \(base)"
        }
        return base
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

    private static func tile(_ event: EventModel, tomorrow: Bool) -> TodayTileEvent {
        TodayTileEvent(
            title: event.title, start: event.start, isAllDay: event.isAllDay,
            color: Color(nsColor: event.calendar.color), isTomorrow: tomorrow)
    }
}

struct TodayTile: View {
    @ObservedObject private var model = TodayTileModel.shared
    let onTap: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            TodayTileView(
                date: context.date,
                event: model.nextEvent(now: context.date),
                access: model.access,
                onTap: onTap,
                onRequestAccess: { model.requestAccess() })
        }
        .onAppear { model.refresh() }
    }
}
