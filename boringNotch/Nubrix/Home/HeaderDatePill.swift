import SwiftUI

enum HeaderDatePillFormat {
    static func label(_ date: Date, locale: Locale) -> String {
        var weekday = Date.FormatStyle(date: .omitted, time: .omitted).weekday(.abbreviated)
        weekday.locale = locale
        let day = Calendar.current.component(.day, from: date)
        return "\(date.formatted(weekday)) \(day)"
    }

    static func help(event: TodayTileEvent?, access: TodayTileAccess, locale: Locale) -> String {
        guard access == .granted else { return "Calendar" }
        guard let event else { return "No upcoming events" }
        let time: String
        if event.isAllDay {
            time = "All-day"
        } else if event.isTomorrow {
            time = "\(TodayTileFormat.tomorrowWord(locale: locale)) \(TodayTileFormat.time(event.start, locale: locale))"
        } else {
            time = TodayTileFormat.time(event.start, locale: locale)
        }
        return "\(time) · \(event.title)"
    }
}

struct HeaderDatePillView: View {
    let date: Date
    let dotColor: Color?
    let help: String
    var active = false
    var locale: Locale = .autoupdatingCurrent
    var action: () -> Void = {}

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(HeaderDatePillFormat.label(date, locale: locale))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 5)
                .frame(height: 26)
                .background(
                    Color.white.opacity(active ? 0.2 : hovering ? 0.14 : 0.08),
                    in: Capsule())
                .overlay(alignment: .topTrailing) {
                    if let dotColor {
                        Circle()
                            .fill(dotColor)
                            .frame(width: 5, height: 5)
                            .padding(.top, 4)
                            .padding(.trailing, 2)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.15), value: hovering)
        .help(help)
    }
}

struct HeaderDatePill: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var model = TodayTileModel.shared
    @ObservedObject private var host = NotchExtensionHost.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HeaderDatePillView(
                date: context.date,
                dotColor: model.dotEvent(now: context.date)?.color,
                help: HeaderDatePillFormat.help(
                    event: model.nextEvent(now: context.date),
                    access: model.access,
                    locale: .autoupdatingCurrent),
                active: host.currentID == NubrixCalendarSheet.extensionID && host.phase != .closing,
                action: toggle)
        }
        .onAppear { model.refresh() }
        .onChange(of: vm.notchState) { _, state in
            if state == .open { model.refresh() }
        }
    }

    private func toggle() {
        NubrixCalendarSheet.toggle(screenUUID: vm.screenUUID)
    }
}
