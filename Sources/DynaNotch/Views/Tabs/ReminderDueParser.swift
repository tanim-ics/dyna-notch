import Foundation
import EventKit
import os

/// Natural-language due dates for the Reminders tab ("Call mom tomorrow 9", "Pay rent on Oct 28").
/// NSDataDetector finds the date; a bare hour right after it ("tomorrow 9", "friday at 7pm") is folded in.
struct ReminderDue: Equatable {
    var title: String
    var due: Date
    var hasTime: Bool
    var phrase: String
}

enum ReminderDueParser {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    static func parse(_ text: String, calendar: Calendar = .current) -> ReminderDue? {
        let ns = text as NSString
        guard let detector = detector,
              let match = detector.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              var date = match.date else { return nil }
        var range = match.range
        var phrase = ns.substring(with: range)
        let lower = phrase.lowercased()
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        var hasTime = lower.contains(":") || lower.contains("am") || lower.contains("pm") || lower.contains(" at ")
            || lower.contains("noon") || lower.contains("midnight") || comps.hour != 12 || comps.minute != 0

        // "tomorrow 9" / "tomorrow at 9" / "tomorrow 9pm": NSDataDetector only takes "tomorrow".
        if !hasTime {
            let rest = ns.substring(from: range.location + range.length)
            if let regex = try? NSRegularExpression(pattern: "^\\s+(?:at\\s+)?(\\d{1,2})\\s*(am|pm)?\\b", options: [.caseInsensitive]),
               let m = regex.firstMatch(in: rest, range: NSRange(location: 0, length: (rest as NSString).length)),
               var hour = Int((rest as NSString).substring(with: m.range(at: 1))) {
                let suffixRange = m.range(at: 2)
                if suffixRange.location != NSNotFound {
                    let suffix = (rest as NSString).substring(with: suffixRange).lowercased()
                    if suffix == "pm" && hour < 12 { hour += 12 }
                    if suffix == "am" && hour == 12 { hour = 0 }
                }
                if (0...23).contains(hour), let withHour = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) {
                    date = withHour
                    hasTime = true
                    range = NSRange(location: range.location, length: range.length + m.range.length)
                    phrase = ns.substring(with: range)
                }
            }
        }

        // Strip the phrase and a dangling "on" / "at" / "by" / "due" before it.
        var title = ns.replacingCharacters(in: range, with: " ")
        if let regex = try? NSRegularExpression(pattern: "\\s+(on|at|by|due)\\s*$", options: [.caseInsensitive]) {
            let before = (title as NSString).substring(to: min(range.location, (title as NSString).length))
            let after = (title as NSString).substring(from: min(range.location, (title as NSString).length))
            let trimmedBefore = regex.stringByReplacingMatches(in: before, range: NSRange(location: 0, length: (before as NSString).length),
                                                               withTemplate: "")
            title = trimmedBefore + after
        }
        title = title.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        if !hasTime { date = calendar.startOfDay(for: date) }
        return ReminderDue(title: title, due: date, hasTime: hasTime, phrase: phrase.trimmingCharacters(in: .whitespaces))
    }

    /// "Due tomorrow 09:00" chip text.
    static func chipText(_ due: ReminderDue, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = due.hasTime ? " " + due.due.formatted(date: .omitted, time: .shortened) : ""
        if calendar.isDateInToday(due.due) { return "Due today" + time }
        if calendar.isDateInTomorrow(due.due) { return "Due tomorrow" + time }
        return "Due " + due.due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + time
    }
}

/// Saves a reminder with a due date (RemindersService.add has no due parameter); the service reloads on the
/// EKEventStoreChanged notification this posts.
enum ReminderComposer {
    private static let store = EKEventStore()
    private static let logger = Logger(subsystem: "com.tanim.dynanotch", category: "Reminders")

    @discardableResult
    static func add(title: String, due: Date, hasTime: Bool) -> Bool {
        guard let list = store.defaultCalendarForNewReminders() else { return false }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title.isEmpty ? "Reminder" : title
        reminder.calendar = list
        let units: Set<Calendar.Component> = hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
        reminder.dueDateComponents = Calendar.current.dateComponents(units, from: due)
        if hasTime { reminder.addAlarm(EKAlarm(absoluteDate: due)) }
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            logger.error("Saving reminder failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
