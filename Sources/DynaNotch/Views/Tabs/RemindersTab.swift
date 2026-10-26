import SwiftUI
import AppKit
import DynaNotchCore

/// Apple Reminders: incomplete reminders with due dates, quick add, tick to complete.
struct RemindersTab: View {
    @EnvironmentObject var reminders: RemindersService

    @State private var newTitle = ""

    var body: some View {
        Group {
            switch reminders.access {
            case .granted:
                content
            case .notDetermined:
                VStack(spacing: 8) {
                    PanelEmptyState(symbol: "checklist", title: "Show your Reminders here",
                                    detail: "DynaNotch needs access to Reminders to list and complete them")
                    PanelPillButton(title: "Allow Access", symbol: "lock.open") { reminders.requestAccess() }
                }
            case .denied:
                VStack(spacing: 8) {
                    PanelEmptyState(symbol: "lock.fill", title: "No access to Reminders",
                                    detail: "Allow DynaNotch in System Settings › Privacy & Security › Reminders")
                    PanelPillButton(title: "Open System Settings", symbol: "gearshape") { reminders.openSystemSettings() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { reminders.start() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text("Reminders")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text("\(reminders.items.count)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(PanelStyle.secondary)
                }
                PanelInputField(symbol: "plus", placeholder: "New reminder — try “Call mom tomorrow 9”", text: $newTitle,
                                onSubmit: add)
                    .uiTestID("reminders.field")
                if let due = parsedDue {
                    DueChip(text: ReminderDueParser.chipText(due))
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                PanelIconButton(symbol: "arrow.up.forward.app", size: 11, help: "Open Reminders") {
                    reminders.openRemindersApp()
                }
            }
            if reminders.items.isEmpty {
                PanelEmptyState(symbol: "checkmark.circle", title: reminders.isLoading ? "Loading…" : "All done",
                                detail: reminders.isLoading ? nil : "No open reminders")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(reminders.items) { item in
                            ReminderRow(item: item)
                        }
                    }
                }
            }
        }
    }

    /// Due date typed into the title ("tomorrow 9"), previewed as a chip and stripped from the saved title.
    private var parsedDue: ReminderDue? {
        let text = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return ReminderDueParser.parse(text)
    }

    private func add() {
        let text = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let due = ReminderDueParser.parse(text) {
            if ReminderComposer.add(title: due.title, due: due.due, hasTime: due.hasTime) {
                reminders.refresh()
            }
        } else {
            reminders.add(text)
        }
        newTitle = ""
    }
}

/// "📅 Due tomorrow 9:00" preview while typing.
private struct DueChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Capsule().fill(PanelStyle.today.opacity(0.6)))
        .fixedSize()
        .uiTestID("reminders.dueChip")
    }
}

private struct ReminderRow: View {
    let item: ReminderItem

    @EnvironmentObject var reminders: RemindersService
    @State private var hovering = false
    @State private var ticking = false

    private var listColor: Color {
        item.listColorHex.flatMap { HexColor.color($0) } ?? PanelStyle.today
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { ticking = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    reminders.complete(item)
                }
            } label: {
                Image(systemName: ticking ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(ticking ? listColor : listColor.opacity(0.8))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Complete")

            Text(item.title.isEmpty ? "Untitled" : item.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(ticking ? 0.4 : 0.9))
                .strikethrough(ticking)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let due = item.due {
                Text(dueText(due))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isOverdue(due) ? IslandColors.low : PanelStyle.secondary)
                    .lineLimit(1)
            }
            if !item.listName.isEmpty {
                HStack(spacing: 3) {
                    Circle().fill(listColor).frame(width: 5, height: 5)
                    Text(item.listName)
                        .font(.system(size: 9))
                        .foregroundStyle(PanelStyle.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 90, alignment: .trailing)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.08 : 0))
        )
        .onHover { hovering = $0 }
    }

    private func isOverdue(_ due: Date) -> Bool {
        if item.hasDueTime { return due < Date() }
        return due < Calendar.current.startOfDay(for: Date())
    }

    private func dueText(_ due: Date) -> String {
        let cal = Calendar.current
        let time = item.hasDueTime ? " " + due.formatted(date: .omitted, time: .shortened) : ""
        if cal.isDateInToday(due) { return "Today" + time }
        if cal.isDateInTomorrow(due) { return "Tomorrow" + time }
        if cal.isDateInYesterday(due) { return "Yesterday" + time }
        let sameYear = cal.component(.year, from: due) == cal.component(.year, from: Date())
        let date = sameYear
            ? due.formatted(.dateTime.day().month(.abbreviated))
            : due.formatted(.dateTime.day().month(.abbreviated).year())
        return date + time
    }
}
