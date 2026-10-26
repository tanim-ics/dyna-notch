import AppKit
import Combine
import EventKit
import Foundation
import os
import SwiftUI
import DynaNotchCore

/// One EventKit calendar for the settings list.
struct CalendarInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let colorHex: String?
    let source: String
}

/// Lets callers write either `CalendarAccess` or `CalendarService.CalendarAccess`.
typealias CalendarAccess = CalendarService.CalendarAccess

/// Today's and tomorrow's events via EventKit, plus "starting soon" alerts.
final class CalendarService: ObservableObject {
    enum CalendarAccess {
        case notDetermined
        case denied
        case granted
    }

    static let shared = CalendarService()

    @Published private(set) var upcoming: [CalendarItem] = []
    /// Every event calendar (Settings → Calendar → per-calendar toggles; hidden ids in settings.hiddenCalendars).
    @Published private(set) var calendars: [CalendarInfo] = []
    @Published private(set) var access: CalendarAccess = .notDetermined
    /// Bumped whenever the event store changes or the Calendar tab edits an event (views re-fetch their range).
    @Published private(set) var revision = 0

    let dueSoon = PassthroughSubject<CalendarItem, Never>()
    /// Video-call links (Zoom, Meet, Teams …) found in an event's URL, location or notes, by `CalendarItem.id`.
    private(set) var meetingLinks: [String: URL] = [:]

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "calendar")
    private let store = EKEventStore()
    private let fetchQueue = DispatchQueue(label: "com.tanim.dynanotch.calendar", qos: .utility)
    private var started = false
    private var items: [CalendarItem] = []
    private var tracker = CalendarAlertTracker()
    private var cancellables = Set<AnyCancellable>()
    private var fetchGeneration = 0

    private init() {
        access = CalendarService.currentAccess()
    }

    func start() {
        guard !started else { return }
        started = true
        access = CalendarService.currentAccess()

        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.revision += 1
                self?.refresh()
            }
            .store(in: &cancellables)

        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.checkDue() }
            .store(in: &cancellables)

        // Per-calendar toggles: re-filter when the hidden list changes.
        AppSettings.shared.$hiddenCalendars
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        if access == .granted { refresh() }
    }

    /// The next meeting with a join link that has not ended (current meetings first), for ⌃⌥J.
    func nextMeetingURL(now: Date = Date()) -> URL? {
        let candidates = items
            .filter { !$0.isAllDay && $0.end > now && meetingLinks[$0.id] != nil }
            .sorted { $0.start < $1.start }
        // Only meetings starting within the next 12 hours (or already running).
        guard let item = candidates.first(where: { $0.start.timeIntervalSince(now) < 12 * 3600 }) else { return nil }
        return meetingLinks[item.id]
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.logger.error("calendar access request failed: \(error.localizedDescription, privacy: .public)")
                }
                self.access = granted ? .granted : CalendarService.currentAccess()
                if self.access == .granted { self.refresh() }
            }
        }
    }

    func colorFor(_ item: CalendarItem) -> Color {
        guard let rgb = CalendarService.parseHex(item.colorHex) else { return .blue }
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    // MARK: Calendar tab (month range, add / edit / delete)

    /// Events of visible calendars overlapping [start, end), sorted (all-day first per day). Completion on main.
    func events(from start: Date, to end: Date, completion: @escaping ([CalendarItem]) -> Void) {
        guard CalendarService.currentAccess() == .granted, end > start else {
            completion([])
            return
        }
        let store = self.store
        let hidden = CalendarService.hiddenIDs()
        fetchQueue.async {
            let visible = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
            var result: [CalendarItem] = []
            if !visible.isEmpty {
                let predicate = store.predicateForEvents(withStart: start, end: end, calendars: visible)
                result = store.events(matching: predicate).compactMap(CalendarService.makeItem)
            }
            result.sort { a, b in
                if a.isAllDay != b.isAllDay && Calendar.current.isDate(a.start, inSameDayAs: b.start) { return a.isAllDay }
                return a.start < b.start
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Visible calendars new events can be saved to (title order, default calendar first).
    func writableCalendars() -> [CalendarInfo] {
        guard CalendarService.currentAccess() == .granted else { return [] }
        let hidden = CalendarService.hiddenIDs()
        let defaultID = store.defaultCalendarForNewEvents?.calendarIdentifier
        return store.calendars(for: .event)
            .filter { $0.allowsContentModifications && !hidden.contains($0.calendarIdentifier) }
            .map { calendar -> CalendarInfo in
                let source: EKSource? = calendar.source
                return CalendarInfo(id: calendar.calendarIdentifier, title: calendar.title,
                                    colorHex: CalendarService.hexString(calendar.color), source: source?.title ?? "")
            }
            .sorted { a, b in
                if a.id == defaultID { return true }
                if b.id == defaultID { return false }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
    }

    var defaultCalendarID: String? { store.defaultCalendarForNewEvents?.calendarIdentifier }

    /// Saves a new timed event. Returns an error message, or nil on success.
    @discardableResult
    func addEvent(title: String, start: Date, duration: TimeInterval, calendarID: String?) -> String? {
        guard CalendarService.currentAccess() == .granted else { return "No calendar access" }
        let event = EKEvent(eventStore: store)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.title = trimmed.isEmpty ? "New Event" : trimmed
        event.startDate = start
        event.endDate = start.addingTimeInterval(max(300, duration))
        let chosen = calendarID.flatMap { store.calendar(withIdentifier: $0) }
        guard let calendar = chosen ?? store.defaultCalendarForNewEvents else { return "No calendar to save to" }
        event.calendar = calendar
        return commit { try self.store.save(event, span: .thisEvent, commit: true) }
    }

    /// Changes title / time of one occurrence (identified by id + its original start).
    @discardableResult
    func updateEvent(_ item: CalendarItem, title: String, start: Date, duration: TimeInterval) -> String? {
        guard let event = occurrence(of: item) else { return "Event not found" }
        guard event.calendar?.allowsContentModifications ?? false else { return "This calendar is read-only" }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { event.title = trimmed }
        if !item.isAllDay {
            event.startDate = start
            event.endDate = start.addingTimeInterval(max(300, duration))
        }
        return commit { try self.store.save(event, span: .thisEvent, commit: true) }
    }

    /// Deletes one occurrence.
    @discardableResult
    func deleteEvent(_ item: CalendarItem) -> String? {
        guard let event = occurrence(of: item) else { return "Event not found" }
        guard event.calendar?.allowsContentModifications ?? false else { return "This calendar is read-only" }
        return commit { try self.store.remove(event, span: .thisEvent, commit: true) }
    }

    func canEdit(_ item: CalendarItem) -> Bool {
        guard let event = store.event(withIdentifier: item.id) else { return false }
        return event.calendar?.allowsContentModifications ?? false
    }

    func openCalendarApp() {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    private func occurrence(of item: CalendarItem) -> EKEvent? {
        guard CalendarService.currentAccess() == .granted else { return nil }
        let predicate = store.predicateForEvents(withStart: item.start.addingTimeInterval(-1),
                                                 end: item.start.addingTimeInterval(86_400), calendars: nil)
        let match = store.events(matching: predicate).first { event in
            let id: String? = event.eventIdentifier
            let start: Date? = event.startDate
            return id == item.id && start.map { abs($0.timeIntervalSince(item.start)) < 1 } == true
        }
        return match ?? store.event(withIdentifier: item.id)
    }

    private func commit(_ work: () throws -> Void) -> String? {
        do {
            try work()
            revision += 1
            refresh()
            return nil
        } catch {
            logger.error("calendar edit failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }

    // MARK: Private

    private static func currentAccess() -> CalendarAccess {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess { return .granted }   // `.authorized` has the same raw value
        if status == .notDetermined { return .notDetermined }
        return .denied   // denied, restricted, writeOnly, unknown
    }

    /// Ids from settings.hiddenCalendars (comma separated).
    static func hiddenIDs() -> Set<String> {
        Set(AppSettings.shared.hiddenCalendars.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }

    private func refresh() {
        let current = CalendarService.currentAccess()
        if access != current { access = current }
        guard current == .granted else {
            if !upcoming.isEmpty { upcoming = [] }
            if !calendars.isEmpty { calendars = [] }
            items = []
            return
        }
        fetchGeneration += 1
        let generation = fetchGeneration
        let store = self.store
        let hidden = CalendarService.hiddenIDs()
        fetchQueue.async { [weak self] in
            let now = Date()
            let startOfToday = Calendar.current.startOfDay(for: now)
            let end = now.addingTimeInterval(36 * 3600)
            let allCalendars = store.calendars(for: .event)
            let infos = allCalendars.map { calendar -> CalendarInfo in
                let source: EKSource? = calendar.source
                return CalendarInfo(id: calendar.calendarIdentifier, title: calendar.title,
                                    colorHex: CalendarService.hexString(calendar.color),
                                    source: source?.title ?? "")
            }.sorted { ($0.source, $0.title) < ($1.source, $1.title) }
            let visible = allCalendars.filter { !hidden.contains($0.calendarIdentifier) }
            var events: [EKEvent] = []
            if !visible.isEmpty {
                let predicate = store.predicateForEvents(withStart: startOfToday, end: end, calendars: visible)
                events = store.events(matching: predicate)
            }
            var fetched: [CalendarItem] = []
            var links: [String: URL] = [:]
            for event in events {
                guard let item = CalendarService.makeItem(event) else { continue }
                fetched.append(item)
                if let link = CalendarService.meetingLink(event) { links[item.id] = link }
            }
            DispatchQueue.main.async {
                guard let self = self, generation == self.fetchGeneration else { return }
                if infos != self.calendars { self.calendars = infos }
                self.meetingLinks = links
                self.items = fetched
                let next = CalendarFilter.upcoming(fetched, now: Date(), limit: 6)
                if next != self.upcoming { self.upcoming = next }
                self.checkDue()
            }
        }
    }

    private func checkDue() {
        guard access == .granted, !items.isEmpty else { return }
        let now = Date()
        let due = tracker.due(events: items, now: now, leadMinutes: AppSettings.shared.calendarLeadMinutes)
        let onlyWithLink = AppSettings.shared.meetingOnlyWithLink
        for item in due where !onlyWithLink || meetingURL(for: item) != nil { dueSoon.send(item) }
        let next = CalendarFilter.upcoming(items, now: now, limit: 6)
        if next != upcoming { upcoming = next }
    }

    private static func makeItem(_ event: EKEvent) -> CalendarItem? {
        let start: Date? = event.startDate
        let end: Date? = event.endDate
        guard let startDate = start else { return nil }
        let endDate = end ?? startDate
        let identifier: String? = event.eventIdentifier
        let title: String? = event.title
        let calendar: EKCalendar? = event.calendar
        let location: String? = event.location
        var colorHex: String?
        if let calendar = calendar {
            let color: NSColor? = calendar.color
            colorHex = hexString(color)
        }
        let id = (identifier?.isEmpty == false) ? (identifier ?? "") : UUID().uuidString
        let trimmedTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CalendarItem(
            id: id,
            title: trimmedTitle.isEmpty ? "Untitled" : trimmedTitle,
            start: startDate,
            end: endDate,
            isAllDay: event.isAllDay,
            location: (trimmedLocation?.isEmpty == false) ? trimmedLocation : nil,
            colorHex: colorHex
        )
    }

    func meetingURL(for item: CalendarItem) -> URL? {
        meetingLinks[item.id]
    }

    private static func meetingLink(_ event: EKEvent) -> URL? {
        let url: URL? = event.url
        let location: String? = event.location
        let notes: String? = event.hasNotes ? event.notes : nil
        return MeetingLink.detect(in: [url?.absoluteString, location, notes])
    }

    private static func hexString(_ color: NSColor?) -> String? {
        guard let srgb = color?.usingColorSpace(.sRGB) else { return nil }
        let r = Int((min(max(srgb.redComponent, 0), 1) * 255).rounded())
        let g = Int((min(max(srgb.greenComponent, 0), 1) * 255).rounded())
        let b = Int((min(max(srgb.blueComponent, 0), 1) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private static func parseHex(_ hex: String?) -> (r: Double, g: Double, b: Double)? {
        guard var text = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (r, g, b)
    }
}
