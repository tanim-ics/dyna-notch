import AppKit
import Combine
import EventKit
import os

struct ReminderItem: Identifiable, Equatable {
    let id: String
    var title: String
    var due: Date?
    var listName: String
    var isCompleted: Bool
    /// True when the due date has a time component (otherwise it is a whole-day reminder).
    var hasDueTime: Bool = false
    var listColorHex: String?
}

/// Apple Reminders through EventKit.
final class RemindersService: ObservableObject {
    enum Access { case notDetermined, denied, granted }

    static let shared = RemindersService()

    @Published private(set) var items: [ReminderItem] = []
    @Published private(set) var access: Access = .notDetermined
    @Published private(set) var isLoading = false

    private let store = EKEventStore()
    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "Reminders")
    private var cancellables = Set<AnyCancellable>()
    private var started = false
    private var fetchGeneration = 0

    private init() {}

    func start() {
        updateAccess()
        guard !started else {
            refresh()
            return
        }
        started = true
        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        refresh()
    }

    func requestAccess() {
        let handler: (Bool, Error?) -> Void = { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.logger.error("Reminders access error: \(error.localizedDescription, privacy: .public)")
                }
                self.access = granted ? .granted : .denied
                if granted { self.refresh() }
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToReminders(completion: handler)
        } else {
            store.requestAccess(to: .reminder, completion: handler)
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    func openRemindersApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    func refresh() {
        updateAccess()
        guard access == .granted else {
            if !items.isEmpty { items = [] }
            return
        }
        fetchGeneration += 1
        let generation = fetchGeneration
        isLoading = true
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let mapped = (reminders ?? []).map(Self.makeItem)
            let sorted = mapped.sorted(by: Self.order)
            DispatchQueue.main.async {
                guard let self = self, generation == self.fetchGeneration else { return }
                self.isLoading = false
                if sorted != self.items { self.items = sorted }
            }
        }
    }

    func add(_ title: String) {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, access == .granted else { return }
        guard let calendar = store.defaultCalendarForNewReminders() else {
            logger.error("No default reminders list")
            return
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = text
        reminder.calendar = calendar
        do {
            try store.save(reminder, commit: true)
            refresh()
        } catch {
            logger.error("Saving reminder failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func complete(_ item: ReminderItem) {
        guard access == .granted, let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        // Optimistic removal so the row disappears immediately.
        items.removeAll { $0.id == item.id }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
        } catch {
            logger.error("Completing reminder failed: \(error.localizedDescription, privacy: .public)")
            refresh()
        }
    }

    // MARK: - Private

    private func updateAccess() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        let value: Access
        switch status {
        case .notDetermined: value = .notDetermined
        case .denied, .restricted, .writeOnly: value = .denied
        default: value = .granted   // .fullAccess (and legacy .authorized)
        }
        if value != access { access = value }
    }

    private static func makeItem(_ reminder: EKReminder) -> ReminderItem {
        var due: Date?
        var hasTime = false
        if let components = reminder.dueDateComponents {
            due = Calendar.current.date(from: components)
            hasTime = components.hour != nil
        }
        return ReminderItem(id: reminder.calendarItemIdentifier,
                            title: reminder.title ?? "",
                            due: due,
                            listName: reminder.calendar?.title ?? "",
                            isCompleted: reminder.isCompleted,
                            hasDueTime: hasTime,
                            listColorHex: reminder.calendar.flatMap { hex($0.color) })
    }

    /// Due reminders first (earliest first), then undated ones alphabetically.
    private static func order(_ a: ReminderItem, _ b: ReminderItem) -> Bool {
        switch (a.due, b.due) {
        case let (x?, y?): return x < y
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    private static func hex(_ color: NSColor?) -> String? {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return nil }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
