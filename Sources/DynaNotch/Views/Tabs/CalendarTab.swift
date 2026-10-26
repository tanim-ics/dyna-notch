import SwiftUI
import AppKit
import DynaNotchCore

/// Calendar: month grid (‹ ›, today, event dots) | agenda for the selected day with due reminders;
/// add, edit and delete events through EventKit (CalendarService).
struct CalendarTab: View {
    @EnvironmentObject var calendar: CalendarService

    var body: some View {
        Group {
            switch calendar.access {
            case .granted:
                CalendarTabContent()
            case .notDetermined:
                VStack(spacing: 8) {
                    PanelEmptyState(symbol: "calendar", title: "Show your calendar here",
                                    detail: "DynaNotch needs access to Calendar to show, add and edit events")
                    PanelPillButton(title: "Allow Access", symbol: "lock.open") { calendar.requestAccess() }
                        .uiTestID("calendar.allow")
                }
            case .denied:
                VStack(spacing: 8) {
                    PanelEmptyState(symbol: "lock.fill", title: "No access to Calendar",
                                    detail: "Allow DynaNotch in System Settings › Privacy & Security › Calendars")
                    PanelPillButton(title: "Open System Settings", symbol: "gearshape") { Permissions.openCalendarSettings() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Draft for the inline add / edit form.
struct EventDraft: Equatable {
    var item: CalendarItem?          // nil = new event
    var title: String
    var start: Date
    var duration: TimeInterval
    var calendarID: String?
}

private struct CalendarTabContent: View {
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var reminders: RemindersService

    @State private var month: Date = Calendar.current.startOfDay(for: Date())
    @State private var selected: Date = Calendar.current.startOfDay(for: Date())
    @State private var events: [CalendarItem] = []
    @State private var draft: EventDraft?

    private let cal = Calendar.current

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CalendarMonthGrid(month: $month, selected: $selected, events: events)
                .frame(width: 206)
            Group {
                if let current = draft {
                    EventEditor(draft: current,
                                onSave: { saved in save(saved) },
                                onDelete: { item in delete(item) },
                                onCancel: { draft = nil })
                        .id(current.item?.id ?? "new")
                } else {
                    agenda
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            reload()
            if reminders.access == .granted { reminders.start() }
        }
        .onChange(of: month) { reload() }
        .onChange(of: calendar.revision) { reload() }
        .onChange(of: settings.hiddenCalendars) { reload() }
    }

    // MARK: Agenda

    private var dayEvents: [CalendarItem] {
        let start = cal.startOfDay(for: selected)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events.filter { $0.start < end && $0.end > start || ($0.start >= start && $0.start < end) }
    }

    private var dayReminders: [ReminderItem] {
        reminders.items.filter { item in
            guard let due = item.due else { return false }
            return cal.isDate(due, inSameDayAs: selected)
        }
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(dayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(countText)
                    .font(.system(size: 10))
                    .foregroundStyle(PanelStyle.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                PanelIconButton(symbol: "arrow.up.forward.app", size: 10, frame: 20, help: "Open Calendar") {
                    calendar.openCalendarApp()
                }
                PanelPillButton(title: "Add", symbol: "plus", tint: PanelStyle.today.opacity(0.75)) {
                    draft = newDraft()
                }
                .uiTestID("calendar.add")
            }
            if dayEvents.isEmpty && dayReminders.isEmpty {
                PanelEmptyState(symbol: "calendar.badge.plus", title: "Nothing planned",
                                detail: "Click Add to create an event on this day")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(dayEvents) { item in
                            AgendaEventRow(item: item, color: calendar.colorFor(item)) {
                                draft = EventDraft(item: item, title: item.title, start: item.start,
                                                   duration: max(300, item.end.timeIntervalSince(item.start)),
                                                   calendarID: nil)
                            }
                        }
                        if !dayReminders.isEmpty {
                            PanelCaption("Reminders due")
                                .padding(.top, 4)
                            ForEach(dayReminders) { item in
                                AgendaReminderRow(item: item)
                            }
                        }
                    }
                }
            }
        }
    }

    private var dayTitle: String {
        if cal.isDateInToday(selected) { return "Today" }
        if cal.isDateInTomorrow(selected) { return "Tomorrow" }
        return selected.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private var countText: String {
        let n = dayEvents.count
        return n == 0 ? "" : (n == 1 ? "1 event" : "\(n) events")
    }

    private func newDraft() -> EventDraft {
        let now = Date()
        var start: Date
        if cal.isDate(selected, inSameDayAs: now) {
            // Next half hour.
            let minute = cal.component(.minute, from: now)
            let add = minute < 30 ? 30 - minute : 60 - minute
            start = cal.date(byAdding: .minute, value: add, to: now) ?? now
            start = cal.date(bySetting: .second, value: 0, of: start) ?? start
        } else {
            start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: selected) ?? selected
        }
        return EventDraft(item: nil, title: "", start: start, duration: 3600, calendarID: calendar.defaultCalendarID)
    }

    // MARK: Data

    private func reload() {
        guard let range = CalendarMonthGrid.gridRange(for: month, calendar: cal) else { return }
        calendar.events(from: range.start, to: range.end) { items in
            events = items
        }
    }

    private func save(_ d: EventDraft) -> String? {
        let error: String?
        if let item = d.item {
            error = calendar.updateEvent(item, title: d.title, start: d.start, duration: d.duration)
        } else {
            error = calendar.addEvent(title: d.title, start: d.start, duration: d.duration, calendarID: d.calendarID)
        }
        if error == nil {
            selected = cal.startOfDay(for: d.start)
            draft = nil
            reload()
        }
        return error
    }

    private func delete(_ item: CalendarItem) -> String? {
        let error = calendar.deleteEvent(item)
        if error == nil {
            draft = nil
            reload()
        }
        return error
    }
}

// MARK: - Month grid

struct CalendarMonthGrid: View {
    @Binding var month: Date
    @Binding var selected: Date
    let events: [CalendarItem]

    private let cal = Calendar.current

    private struct Day: Identifiable {
        let id: Int
        let date: Date
        let inMonth: Bool
    }

    /// First and last+1 day shown by the grid (whole weeks around the month).
    static func gridRange(for month: Date, calendar cal: Calendar) -> (start: Date, end: Date)? {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return nil }
        let weekday = cal.component(.weekday, from: interval.start)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        guard let start = cal.date(byAdding: .day, value: -leading, to: interval.start),
              let days = cal.range(of: .day, in: .month, for: month)?.count else { return nil }
        let total = Int((Double(leading + days) / 7).rounded(.up)) * 7
        guard let end = cal.date(byAdding: .day, value: total, to: start) else { return nil }
        return (start, end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                Text(month, format: .dateTime.month(.wide).year())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Spacer(minLength: 2)
                PanelIconButton(symbol: "chevron.left", size: 9, frame: 18, help: "Previous month") { shift(-1) }
                    .uiTestID("calendar.prev")
                Button("Today") {
                    let today = cal.startOfDay(for: Date())
                    month = today
                    selected = today
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(PanelStyle.secondary)
                .uiTestID("calendar.today")
                PanelIconButton(symbol: "chevron.right", size: 9, frame: 18, help: "Next month") { shift(1) }
                    .uiTestID("calendar.next")
            }
            weekdayRow
            grid
        }
    }

    private func shift(_ months: Int) {
        if let next = cal.date(byAdding: .month, value: months, to: month) {
            month = next
            if let first = cal.dateInterval(of: .month, for: next)?.start {
                selected = cal.isDate(next, equalTo: Date(), toGranularity: .month) ? cal.startOfDay(for: Date()) : first
            }
        }
    }

    private var weekdayRow: some View {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let shift = max(0, min(6, cal.firstWeekday - 1))
        let ordered = symbols.count == 7 ? Array(symbols[shift...] + symbols[..<shift]) : symbols
        return HStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { item in
                Text(item.element)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(PanelStyle.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var days: [Day] {
        guard let range = CalendarMonthGrid.gridRange(for: month, calendar: cal) else { return [] }
        var out: [Day] = []
        var date = range.start
        var i = 0
        while date < range.end {
            out.append(Day(id: i, date: date, inMonth: cal.isDate(date, equalTo: month, toGranularity: .month)))
            i += 1
            guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return out
    }

    /// Start-of-day dates that have at least one event.
    private var busyDays: Set<Date> {
        var set = Set<Date>()
        for item in events {
            var day = cal.startOfDay(for: item.start)
            let last = item.end > item.start ? item.end.addingTimeInterval(-1) : item.start
            var guardCount = 0
            while day <= last && guardCount < 42 {
                set.insert(day)
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                guardCount += 1
            }
        }
        return set
    }

    private var grid: some View {
        let all = days
        let busy = busyDays
        let rows = stride(from: 0, to: all.count, by: 7).map { Array(all[$0..<min($0 + 7, all.count)]) }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { row in
                HStack(spacing: 0) {
                    ForEach(row.element) { day in
                        cell(day, busy: busy.contains(cal.startOfDay(for: day.date)))
                    }
                }
            }
        }
    }

    private func cell(_ day: Day, busy: Bool) -> some View {
        let isToday = cal.isDateInToday(day.date)
        let isSelected = cal.isDate(day.date, inSameDayAs: selected)
        return Button {
            selected = cal.startOfDay(for: day.date)
            if !day.inMonth { month = selected }
        } label: {
            VStack(spacing: 1) {
                Text("\(cal.component(.day, from: day.date))")
                    .font(.system(size: 9.5, weight: isToday ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color.white : (day.inMonth ? Color.white.opacity(0.85) : Color.white.opacity(0.25)))
                    .frame(width: 17, height: 15)
                    .background(
                        Circle().fill(isToday ? PanelStyle.today : (isSelected ? Color.white.opacity(0.18) : Color.clear))
                    )
                Circle()
                    .fill(busy ? Color.white.opacity(day.inMonth ? 0.6 : 0.25) : Color.clear)
                    .frame(width: 3, height: 3)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .uiTestID("calendar.day.\(cal.component(.month, from: day.date))-\(cal.component(.day, from: day.date))")
    }
}

// MARK: - Rows

private struct AgendaEventRow: View {
    let item: CalendarItem
    let color: Color
    let onEdit: () -> Void

    @EnvironmentObject var calendar: CalendarService
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(color).frame(width: 3, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(timeText)
                    .font(.system(size: 9.5))
                    .monospacedDigit()
                    .foregroundStyle(PanelStyle.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let link = calendar.meetingURL(for: item), item.end > Date() {
                PanelPillButton(title: "Join", symbol: "video.fill", tint: IslandColors.charging.opacity(0.7)) {
                    NSWorkspace.shared.open(link)
                }
            }
            Image(systemName: "pencil")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(PanelStyle.tertiary)
                .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(hovering ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onEdit)
        .uiTestID("calendar.event.\(item.title)")
        .help("Click to edit")
    }

    private var timeText: String {
        var text = item.isAllDay ? "All day" : Format.clockRange(start: item.start, end: item.end)
        if let location = item.location, !location.isEmpty, !location.lowercased().hasPrefix("http") { text += " · " + location }
        return text
    }
}

private struct AgendaReminderRow: View {
    let item: ReminderItem

    @EnvironmentObject var reminders: RemindersService
    @State private var ticking = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { ticking = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { reminders.complete(item) }
            } label: {
                Image(systemName: ticking ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(item.listColorHex.flatMap { HexColor.color($0) } ?? PanelStyle.today)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Complete")
            Text(item.title.isEmpty ? "Untitled" : item.title)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(ticking ? 0.4 : 0.9))
                .strikethrough(ticking)
                .lineLimit(1)
            Spacer(minLength: 4)
            if item.hasDueTime, let due = item.due {
                Text(due.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9.5))
                    .monospacedDigit()
                    .foregroundStyle(PanelStyle.secondary)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
    }
}

// MARK: - Editor

private struct EventEditor: View {
    let onSave: (EventDraft) -> String?
    let onDelete: (CalendarItem) -> String?
    let onCancel: () -> Void

    @EnvironmentObject var calendar: CalendarService
    @State private var draft: EventDraft
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var calendars: [CalendarInfo] = []

    private static let durations: [(String, TimeInterval)] = [("15m", 900), ("30m", 1800), ("1h", 3600), ("2h", 7200)]

    init(draft: EventDraft, onSave: @escaping (EventDraft) -> String?, onDelete: @escaping (CalendarItem) -> String?,
         onCancel: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    private var isAllDay: Bool { draft.item?.isAllDay ?? false }
    private var readOnly: Bool { draft.item.map { !calendar.canEdit($0) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(draft.item == nil ? "New Event" : "Edit Event")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text(draft.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.system(size: 10))
                    .foregroundStyle(PanelStyle.secondary)
                Spacer(minLength: 0)
                if readOnly {
                    Text("Read-only calendar")
                        .font(.system(size: 10))
                        .foregroundStyle(PanelStyle.tertiary)
                }
            }
            PanelInputField(symbol: "pencil", placeholder: "Title", text: $draft.title, onSubmit: save)
                .uiTestID("calendar.title")
            if isAllDay {
                Text("All-day event · only the title can be changed here")
                    .font(.system(size: 10))
                    .foregroundStyle(PanelStyle.secondary)
            } else {
                timeRow
            }
            HStack(spacing: 6) {
                if draft.item == nil {
                    calendarPicker
                }
                if let error = error {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(IslandColors.low)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let item = draft.item, !readOnly {
                    if confirmDelete {
                        PanelPillButton(title: "Delete Event?", symbol: "trash.fill", tint: IslandColors.low.opacity(0.85)) {
                            error = onDelete(item)
                        }
                        .uiTestID("calendar.confirmDelete")
                    } else {
                        PanelIconButton(symbol: "trash", size: 11, frame: 22, tint: IslandColors.low, help: "Delete") {
                            confirmDelete = true
                        }
                        .uiTestID("calendar.delete")
                    }
                }
                PanelPillButton(title: "Cancel", action: onCancel)
                    .uiTestID("calendar.cancel")
                if !readOnly {
                    PanelPillButton(title: "Save", symbol: "checkmark", tint: PanelStyle.today.opacity(0.8), action: save)
                        .uiTestID("calendar.save")
                }
            }
        }
        .onAppear { calendars = calendar.writableCalendars() }
        .onExitCommand(perform: onCancel)
    }

    private var timeRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(PanelStyle.tertiary)
            PanelIconButton(symbol: "minus", size: 9, frame: 18, help: "15 minutes earlier") { move(-15) }
                .uiTestID("calendar.earlier")
            Text(Format.clockRange(start: draft.start, end: draft.start.addingTimeInterval(draft.duration)))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .frame(minWidth: 96)
            PanelIconButton(symbol: "plus", size: 9, frame: 18, help: "15 minutes later") { move(15) }
                .uiTestID("calendar.later")
            Spacer(minLength: 6)
            ForEach(EventEditor.durations, id: \.0) { item in
                Button {
                    draft.duration = item.1
                } label: {
                    Text(item.0)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(draft.duration == item.1 ? Color.white : PanelStyle.secondary)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Capsule().fill(Color.white.opacity(draft.duration == item.1 ? 0.18 : 0.06)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .uiTestID("calendar.duration.\(item.0)")
            }
        }
    }

    private var calendarPicker: some View {
        let current = calendars.first(where: { $0.id == draft.calendarID }) ?? calendars.first
        return Menu {
            ForEach(calendars) { info in
                Button {
                    draft.calendarID = info.id
                } label: {
                    if info.id == current?.id {
                        Label(info.title, systemImage: "checkmark")
                    } else {
                        Text(info.source.isEmpty ? info.title : "\(info.title) (\(info.source))")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(current?.colorHex.flatMap { HexColor.color($0) } ?? PanelStyle.today)
                    .frame(width: 7, height: 7)
                Text(current?.title ?? "Calendar")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(PanelStyle.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .uiTestID("calendar.calendarMenu")
    }

    private func move(_ minutes: Int) {
        draft.start = draft.start.addingTimeInterval(TimeInterval(minutes * 60))
    }

    private func save() {
        guard !readOnly else { return }
        error = onSave(draft)
    }
}
