import AppKit
import Combine
import EventKit
import Foundation
import os
import SwiftUI
import DynaNotchCore

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
    @Published private(set) var access: CalendarAccess = .notDetermined

    let dueSoon = PassthroughSubject<CalendarItem, Never>()

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
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.checkDue() }
            .store(in: &cancellables)

        if access == .granted { refresh() }
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

    // MARK: Private

    private static func currentAccess() -> CalendarAccess {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess { return .granted }   // `.authorized` has the same raw value
        if status == .notDetermined { return .notDetermined }
        return .denied   // denied, restricted, writeOnly, unknown
    }

    private func refresh() {
        let current = CalendarService.currentAccess()
        if access != current { access = current }
        guard current == .granted else {
            if !upcoming.isEmpty { upcoming = [] }
            items = []
            return
        }
        fetchGeneration += 1
        let generation = fetchGeneration
        let store = self.store
        fetchQueue.async { [weak self] in
            let now = Date()
            let startOfToday = Calendar.current.startOfDay(for: now)
            let end = now.addingTimeInterval(36 * 3600)
            let predicate = store.predicateForEvents(withStart: startOfToday, end: end, calendars: nil)
            let events = store.events(matching: predicate)
            let fetched = events.compactMap { CalendarService.makeItem($0) }
            DispatchQueue.main.async {
                guard let self = self, generation == self.fetchGeneration else { return }
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
        for item in due { dueSoon.send(item) }
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
