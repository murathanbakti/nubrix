import AppKit
import SwiftUI

struct CalendarPillButton: View {
    let title: String?
    let systemImage: String?
    let action: () -> Void
    @State private var hovering = false

    init(title: String? = nil, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10.5, weight: .semibold))
                }
                if let title {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, title == nil ? 8 : 10)
            .frame(height: 22)
            .background(
                hovering ? Color.white.opacity(0.16) : Color.white.opacity(0.08),
                in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.15), value: hovering)
    }
}

struct ExpandedCalendarHeader: View {
    let selectedDate: Date
    var locale: Locale = .autoupdatingCurrent
    let onBack: () -> Void
    let onToday: () -> Void
    let onOpenCalendar: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            CalendarPillButton(systemImage: "chevron.left", action: onBack)
            CalendarPillButton(title: "Today", action: onToday)
            Text(TodayTileFormat.monthYear(selectedDate, locale: locale))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.leading, 4)
            Spacer(minLength: 8)
            CalendarPillButton(title: "Open Calendar", systemImage: "arrow.up.forward.app", action: onOpenCalendar)
        }
        .frame(height: 26)
    }
}

struct ExpandedCalendarView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @ObservedObject private var tileModel = TodayTileModel.shared
    @State private var selectedDate = Date()
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            ExpandedCalendarHeader(
                selectedDate: selectedDate,
                onBack: onBack,
                onToday: { selectedDate = Date() },
                onOpenCalendar: openCalendarApp)
            HStack(alignment: .top, spacing: 12) {
                leftColumn
                    .frame(width: 236)
                eventsColumn
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .onChange(of: selectedDate) {
            Task { await calendarManager.updateCurrentDate(selectedDate) }
        }
        .onAppear {
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
            }
        }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .top) {
                WheelPicker(selectedDate: $selectedDate, config: Config())
                HStack {
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 18)
                    Spacer()
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 18)
                }
                .allowsHitTesting(false)
            }
            .frame(height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).locale(.autoupdatingCurrent)))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.6))
            }
            .padding(.leading, 12)
            Spacer(minLength: 0)
        }
    }

    private var summary: String {
        let count = EventListView.filteredEvents(events: calendarManager.events).count
        let day = selectedDate.formatted(.dateTime.day().month(.abbreviated).locale(.autoupdatingCurrent))
        switch count {
        case 0: return "\(day) · No events"
        case 1: return "\(day) · 1 event"
        default: return "\(day) · \(count) events"
        }
    }

    @ViewBuilder
    private var eventsColumn: some View {
        if tileModel.access == .needsAccess {
            VStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Color(white: 0.6))
                Button("Allow calendar access") { tileModel.requestAccess() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if EventListView.filteredEvents(events: calendarManager.events).isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(white: 0.55))
                Text(Calendar.current.isDateInToday(selectedDate) ? "No events today" : "No events")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EventListView(events: calendarManager.events)
        }
    }

    private func openCalendarApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

struct CalendarNotchView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var coordinator = BoringViewCoordinator.shared

    var body: some View {
        ExpandedCalendarView(onBack: { withAnimation(.smooth) { coordinator.dismissOverlay() } })
            .onHover { vm.isHoveringCalendar = $0 }
            .onDisappear { vm.isHoveringCalendar = false }
    }
}
