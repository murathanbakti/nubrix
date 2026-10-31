import AppKit
import SwiftUI

struct NubrixCalendarInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let account: String
    let color: NSColor
}

struct NubrixCalendarEvent: Identifiable, Equatable {
    let id: String
    let eventID: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let color: NSColor
    let calendarTitle: String
    let hasRecurrence: Bool

    var openURL: URL? {
        guard !eventID.isEmpty,
              let encoded = eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        var datePart = ""
        if hasRecurrence {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            if !isAllDay { formatter.timeZone = TimeZone(secondsFromGMT: 0) }
            datePart = "/" + formatter.string(from: start)
        }
        return URL(string: "ical://ekevent\(datePart)/\(encoded)?method=show&options=more")
    }
}

struct NubrixEventDraft {
    var title: String
    var isAllDay: Bool
    var start: Date
    var end: Date
    var calendarID: String
    var location: String

    static func defaultStart(day: Date, now: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: day)
        if calendar.isDate(day, inSameDayAs: now) {
            let hour = calendar.component(.hour, from: now)
            return calendar.date(bySettingHour: min(hour + 1, 23), minute: 0, second: 0, of: dayStart) ?? dayStart
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart) ?? dayStart
    }
}

enum NubrixCalendarAccess: Equatable {
    case notDetermined
    case granted
    case denied
}

enum NubrixCalendarMetrics {
    static let fill = Color.white.opacity(0.06)
    static let fillHover = Color.white.opacity(0.11)
    static let stroke = Color.white.opacity(0.08)
    static let meta = Color.white.opacity(0.5)
    static let red = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let radius: CGFloat = 10
}

struct NubrixCalendarText {
    let isTurkish: Bool

    init(locale: Locale) {
        isTurkish = locale.language.languageCode?.identifier == "tr"
    }

    private func pick(_ tr: String, _ en: String) -> String { isTurkish ? tr : en }

    var newEvent: String { pick("Etkinlik", "Event") }
    var goToPlaceholder: String { pick("Tarihe git: 15.03.2027, yarın, +10, pzt", "Go to date: 3/15/2027, tomorrow, +10, mon") }
    var noEvents: String { pick("Bu gün için etkinlik yok", "No events this day") }
    var noEventsHint: String { pick("Eklemek için ⌘N", "Press ⌘N to add one") }
    var allDay: String { pick("Tüm gün", "All day") }
    var titlePlaceholder: String { pick("Etkinlik başlığı", "Event title") }
    var start: String { pick("Başlangıç", "Starts") }
    var end: String { pick("Bitiş", "Ends") }
    var custom: String { pick("Özel", "Custom") }
    var calendarLabel: String { pick("Takvim", "Calendar") }
    var locationPlaceholder: String { pick("Konum (isteğe bağlı)", "Location (optional)") }
    var cancel: String { pick("İptal", "Cancel") }
    var save: String { pick("Kaydet", "Save") }
    var close: String { pick("Kapat (Esc)", "Close (Esc)") }
    var added: String { pick("Eklendi", "Added") }
    var accessTitle: String { pick("Takvim erişimi gerekli", "Calendar access needed") }
    var accessBody: String { pick("Etkinlikleri görmek ve eklemek için Nubrix'in takvimine izin ver.", "Allow Nubrix to read and add calendar events.") }
    var allowAccess: String { pick("Takvim erişimine izin ver", "Allow calendar access") }
    var deniedBody: String { pick("Erişim kapalı. Sistem Ayarları → Gizlilik ve Güvenlik → Takvimler'den Nubrix'e tam erişim ver.", "Access is off. In System Settings → Privacy & Security → Calendars, give Nubrix full access.") }
    var openSettings: String { pick("Sistem Ayarları'nı aç", "Open System Settings") }
    var openCalendar: String { pick("Takvim uygulamasını aç", "Open Calendar") }
    var thisMonth: String { pick("Bu ay", "This month") }
    var parseUnrecognized: String { pick("Anlaşılamadı", "Couldn't read that date") }
    var parseInvalid: String { pick("Geçersiz tarih", "That date doesn't exist") }
    var endBeforeStart: String { pick("Bitiş, başlangıçtan sonra olmalı", "End must be after start") }
    var noWritableCalendar: String { pick("Yazılabilir takvim yok", "No writable calendar") }
    var saveFailed: String { pick("Kaydedilemedi", "Couldn't save") }

    func eventCount(_ count: Int) -> String {
        isTurkish ? "\(count) etkinlik" : (count == 1 ? "1 event" : "\(count) events")
    }

    func duration(_ minutes: Int) -> String {
        switch minutes {
        case 15: return pick("15 dk", "15m")
        case 30: return pick("30 dk", "30m")
        case 60: return pick("1 sa", "1h")
        case 120: return pick("2 sa", "2h")
        default: return "\(minutes)"
        }
    }

    func parseError(_ failure: NubrixDateParseFailure) -> String {
        failure == .invalidDate ? parseInvalid : parseUnrecognized
    }
}

final class NubrixCalendarFormat {
    let calendar: Calendar
    let locale: Locale
    let text: NubrixCalendarText

    private let monthYearFormatter: DateFormatter
    private let dayMonthYearFormatter: DateFormatter
    private let weekdayFormatter: DateFormatter
    private let monthFormatter: DateFormatter
    private let timeFormatter: DateFormatter
    private let relativeFormatter: RelativeDateTimeFormatter

    init(calendar: Calendar) {
        self.calendar = calendar
        let locale = calendar.locale ?? .autoupdatingCurrent
        self.locale = locale
        self.text = NubrixCalendarText(locale: locale)

        func make(_ template: String?) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            if let template { formatter.setLocalizedDateFormatFromTemplate(template) }
            return formatter
        }
        monthYearFormatter = make("LLLLyyyy")
        dayMonthYearFormatter = make("dMMMMyyyy")
        weekdayFormatter = make("EEEE")
        monthFormatter = make("LLLL")
        let time = make(nil)
        time.dateStyle = .none
        time.timeStyle = .short
        timeFormatter = time
        let relative = RelativeDateTimeFormatter()
        relative.locale = locale
        relative.calendar = calendar
        relative.unitsStyle = .full
        relative.dateTimeStyle = .named
        relativeFormatter = relative
    }

    func capitalized(_ string: String) -> String {
        guard let first = string.first else { return string }
        return String(first).uppercased(with: locale) + string.dropFirst()
    }

    func monthYear(_ date: Date) -> String { capitalized(monthYearFormatter.string(from: date)) }
    func dayMonthYear(_ date: Date) -> String { dayMonthYearFormatter.string(from: date) }
    func weekday(_ date: Date) -> String { capitalized(weekdayFormatter.string(from: date)) }
    func longDate(_ date: Date) -> String { "\(dayMonthYear(date)), \(weekday(date))" }
    func time(_ date: Date) -> String { timeFormatter.string(from: date) }

    func monthName(_ month: Int) -> String {
        var components = DateComponents()
        components.year = 2001
        components.month = month
        components.day = 1
        guard let date = calendar.date(from: components) else { return "" }
        return capitalized(monthFormatter.string(from: date))
    }

    func relativeDays(from reference: Date, to date: Date) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: reference), to: calendar.startOfDay(for: date)).day ?? 0
        return relativeFormatter.localizedString(from: DateComponents(day: days))
    }

    var todayLabel: String { capitalized(relativeDays(from: Date(), to: Date())) }

    var weekdayHeaders: [(index: Int, symbol: String)] {
        let symbols = calendar.shortWeekdaySymbols
        return (0..<7).map { offset in
            let weekdayIndex = (calendar.firstWeekday - 1 + offset) % 7
            return (weekdayIndex + 1, capitalized(symbols[weekdayIndex]))
        }
    }

    func timeRange(for event: NubrixCalendarEvent, on day: Date) -> String {
        if event.isAllDay { return text.allDay }
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let shownStart = max(event.start, dayStart)
        let shownEnd = min(event.end, dayEnd)
        if event.end <= event.start { return time(shownStart) }
        return "\(time(shownStart)) – \(time(shownEnd))"
    }
}
