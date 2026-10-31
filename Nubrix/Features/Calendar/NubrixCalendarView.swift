import AppKit
import SwiftUI

enum NubrixCalendarFocus: Hashable {
    case grid
    case goTo
}

struct NubrixCalendarView: View {
    enum Preset {
        case picker
        case form(String)
        case goTo(String)
    }

    enum GoToOutcome: Equatable {
        case none
        case found(Date)
        case failed(String)
    }

    let calendar: Calendar
    let fmt: NubrixCalendarFormat
    let onClose: () -> Void
    let preset: Preset?

    @StateObject var store: NubrixCalendarStore
    @State var selected: Date
    @State var showPicker = false
    @State var pickerYear: Int
    @State var showForm = false
    @State var formSeed = ""
    @State var gotoText = ""
    @State var outcome: GoToOutcome = .none
    @State var toast: String?
    @FocusState var focus: NubrixCalendarFocus?

    init(initialDate: Date = .now, onClose: @escaping () -> Void) {
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = Locale.autoupdatingCurrent
        self.init(initialDate: initialDate, calendar: calendar, store: nil, preset: nil, onClose: onClose)
    }

    init(initialDate: Date, calendar: Calendar, store: NubrixCalendarStore?, preset: Preset?, onClose: @escaping () -> Void) {
        self.calendar = calendar
        self.fmt = NubrixCalendarFormat(calendar: calendar)
        self.onClose = onClose
        self.preset = preset
        _store = StateObject(wrappedValue: store ?? NubrixCalendarStore(calendar: calendar))
        let day = calendar.startOfDay(for: initialDate)
        _selected = State(initialValue: day)
        _pickerYear = State(initialValue: calendar.component(.year, from: day))
    }

    var text: NubrixCalendarText { fmt.text }
    var monthStart: Date { calendar.dateInterval(of: .month, for: selected)?.start ?? selected }

    var body: some View {
        GeometryReader { geo in
            let leftWidth = min(300, max(256, geo.size.width * 0.485))
            HStack(alignment: .top, spacing: 12) {
                leftColumn.frame(width: leftWidth)
                rightColumn.frame(maxWidth: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .environment(\.colorScheme, .dark)
        .background {
            Button("") { openForm() }
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
        }
        .onExitCommand { handleEscape() }
        .task(id: monthStart) { store.loadGrid(containing: selected) }
        .onChange(of: selected) { _, new in
            pickerYear = calendar.component(.year, from: new)
            if case .found(let date) = outcome, !calendar.isDate(date, inSameDayAs: new) { outcome = .none }
        }
        .onChange(of: gotoText) { _, new in
            if !new.isEmpty { outcome = .none } else if case .failed = outcome { outcome = .none }
        }
        .onAppear {
            store.refreshAccess()
            applyPreset()
            if case .none = preset { focus = .grid }
        }
    }

    func applyPreset() {
        guard let preset else { return }
        switch preset {
        case .picker: showPicker = true
        case .form(let seed): formSeed = seed; showForm = true
        case .goTo(let value):
            gotoText = value
            Task { @MainActor in submitGoTo() }
        }
    }

    func select(_ date: Date) {
        selected = calendar.startOfDay(for: date)
    }

    func moveDay(_ delta: Int) {
        if let date = calendar.date(byAdding: .day, value: delta, to: selected) { select(date) }
    }

    func moveMonth(_ delta: Int) {
        if let date = calendar.date(byAdding: .month, value: delta, to: selected) { select(date) }
    }

    func goToday() {
        select(Date())
    }

    func openForm() {
        guard store.access == .granted else { return }
        formSeed = ""
        showPicker = false
        showForm = true
    }

    func closeForm() {
        showForm = false
        focus = .grid
    }

    func handleEscape() {
        if showForm {
            closeForm()
        } else if showPicker {
            showPicker = false
            focus = .grid
        } else if outcome != .none || !gotoText.isEmpty {
            gotoText = ""
            outcome = .none
            focus = .grid
        } else {
            onClose()
        }
    }

    func submitGoTo() {
        let parser = NubrixDateParser(calendar: calendar, now: Date())
        switch parser.parse(gotoText) {
        case .success(let date):
            showPicker = false
            select(date)
            gotoText = ""
            outcome = .found(calendar.startOfDay(for: date))
            focus = .grid
        case .failure(let failure):
            outcome = .failed(text.parseError(failure))
        }
    }

    func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard !showPicker else { return .ignored }
        let command = press.modifiers.contains(.command)
        switch press.key {
        case .leftArrow: command ? moveMonth(-1) : moveDay(-1)
        case .rightArrow: command ? moveMonth(1) : moveDay(1)
        case .upArrow: moveDay(-7)
        case .downArrow: moveDay(7)
        case .pageUp: moveMonth(-1)
        case .pageDown: moveMonth(1)
        case .escape: handleEscape()
        default:
            guard press.characters.lowercased() == "t",
                  press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
            goToday()
        }
        return .handled
    }

    func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toast == message { withAnimation(.easeOut(duration: 0.2)) { toast = nil } }
        }
    }

    var gridDays: [Date] {
        let offset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let first = calendar.date(byAdding: .day, value: -offset, to: monthStart) ?? monthStart
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    var leftColumn: some View {
        VStack(spacing: 6) {
            monthHeader
            if showPicker {
                NubrixMonthPicker(
                    fmt: fmt,
                    year: $pickerYear,
                    selectedMonth: calendar.component(.month, from: selected),
                    selectedYear: calendar.component(.year, from: selected),
                    onPick: pickMonth,
                    onToday: {
                        goToday()
                        showPicker = false
                        focus = .grid
                    })
                .transition(.opacity)
            } else {
                weekdayRow
                dayGrid
            }
        }
        .focusable()
        .focused($focus, equals: .grid)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat], action: handleKey)
    }

    func pickMonth(_ month: Int) {
        var components = DateComponents()
        components.year = pickerYear
        components.month = month
        components.day = 1
        guard let first = calendar.date(from: components) else { return }
        let dayCount = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        let day = min(calendar.component(.day, from: selected), dayCount)
        components.day = day
        if let date = calendar.date(from: components) { select(date) }
        showPicker = false
        focus = .grid
    }

    var monthHeader: some View {
        HStack(spacing: 4) {
            Button {
                showPicker.toggle()
                pickerYear = calendar.component(.year, from: selected)
            } label: {
                HStack(spacing: 4) {
                    Text(fmt.monthYear(selected))
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(NubrixCalendarMetrics.meta)
                        .rotationEffect(.degrees(showPicker ? 180 : 0))
                }
                .foregroundStyle(.white)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(text.isTurkish ? "Ay ve yıl seç" : "Pick month and year")
            Spacer(minLength: 4)
            NubrixCalendarPill(title: fmt.todayLabel) {
                goToday()
                showPicker = false
                focus = .grid
            }
            NubrixCalendarPill(symbol: "chevron.left") { moveMonth(-1); focus = .grid }
            NubrixCalendarPill(symbol: "chevron.right") { moveMonth(1); focus = .grid }
        }
        .frame(height: 26)
    }

    var weekdayRow: some View {
        let selectedWeekday = calendar.component(.weekday, from: selected)
        return HStack(spacing: 0) {
            ForEach(fmt.weekdayHeaders, id: \.index) { header in
                Text(header.symbol)
                    .font(.system(size: 10, weight: header.index == selectedWeekday ? .bold : .medium))
                    .foregroundStyle(header.index == selectedWeekday ? Color.white : Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 14)
    }

    var dayGrid: some View {
        let days = gridDays
        let month = calendar.component(.month, from: selected)
        let today = Date()
        return VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let day = days[row * 7 + column]
                        let events = store.events(on: day)
                        NubrixDayCell(
                            number: calendar.component(.day, from: day),
                            inMonth: calendar.component(.month, from: day) == month,
                            isToday: calendar.isDate(day, inSameDayAs: today),
                            isSelected: calendar.isDate(day, inSameDayAs: selected),
                            dots: dotColors(events),
                            label: fmt.longDate(day)
                        ) {
                            select(day)
                            focus = .grid
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    func dotColors(_ events: [NubrixCalendarEvent]) -> [Color] {
        var seen: [NSColor] = []
        for event in events where !seen.contains(event.color) {
            seen.append(event.color)
            if seen.count == 3 { break }
        }
        return seen.map { Color(nsColor: $0) }
    }
}

struct NubrixCalendarPill: View {
    var title: String?
    var symbol: String?
    let action: () -> Void
    @State private var hovering = false

    init(title: String? = nil, symbol: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let title {
                    Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, title == nil ? 0 : 10)
            .frame(minWidth: title == nil ? 24 : 0)
            .frame(height: 22)
            .background(hovering ? NubrixCalendarMetrics.fillHover : Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct NubrixDayCell: View {
    let number: Int
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let dots: [Color]
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(isToday ? NubrixCalendarMetrics.red : (isSelected ? Color.white.opacity(0.14) : (hovering ? Color.white.opacity(0.08) : .clear)))
                    if isSelected {
                        Circle().strokeBorder(Color.white.opacity(isToday ? 0.95 : 0.8), lineWidth: 1.5)
                    }
                    Text("\(number)")
                        .font(.system(size: 13, weight: isToday || isSelected ? .semibold : .regular))
                        .foregroundStyle(isToday ? Color.white : Color.white.opacity(inMonth ? 0.95 : 0.28))
                }
                .frame(width: 27, height: 27)
                HStack(spacing: 2.5) {
                    ForEach(Array(dots.enumerated()), id: \.offset) { _, color in
                        Circle().fill(color).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
                .opacity(inMonth ? 1 : 0.45)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
    }
}

struct NubrixMonthPicker: View {
    let fmt: NubrixCalendarFormat
    @Binding var year: Int
    let selectedMonth: Int
    let selectedYear: Int
    let onPick: (Int) -> Void
    let onToday: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                NubrixCalendarPill(symbol: "chevron.left.2") { year -= 10 }
                NubrixCalendarPill(symbol: "chevron.left") { year -= 1 }
                Text(String(year))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                NubrixCalendarPill(symbol: "chevron.right") { year += 1 }
                NubrixCalendarPill(symbol: "chevron.right.2") { year += 10 }
            }
            .frame(height: 24)
            VStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(0..<4, id: \.self) { column in
                            let month = row * 4 + column + 1
                            NubrixMonthChip(
                                title: fmt.monthName(month),
                                selected: month == selectedMonth && year == selectedYear
                            ) { onPick(month) }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            NubrixCalendarPill(title: fmt.text.thisMonth, action: onToday)
        }
        .padding(.top, 2)
    }
}

struct NubrixMonthChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    selected ? NubrixCalendarMetrics.red.opacity(0.85) : (hovering ? NubrixCalendarMetrics.fillHover : NubrixCalendarMetrics.fill),
                    in: RoundedRectangle(cornerRadius: NubrixCalendarMetrics.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NubrixCalendarMetrics.radius, style: .continuous).strokeBorder(NubrixCalendarMetrics.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
