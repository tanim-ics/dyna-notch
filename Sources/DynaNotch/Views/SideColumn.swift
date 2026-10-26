import SwiftUI
import AppKit
import DynaNotchCore

/// Right column of the expanded view: date, upcoming events, battery.
struct SideColumn: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var battery: BatteryService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if settings.expandedShowsCalendar {
                dateHeader
                calendarSection
            }
            Spacer(minLength: 0)
            if settings.expandedShowsBattery, let info = battery.info {
                BatteryRow(info: info)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dateHeader: some View {
        Text(Date(), format: .dateTime.weekday(.abbreviated).day())
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white)
    }

    @ViewBuilder
    private var calendarSection: some View {
        if calendar.access == .granted {
            eventList
        } else if calendar.access == .notDetermined {
            Button("Connect Calendar") { calendar.requestAccess() }
                .buttonStyle(PressableButtonStyle())
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.14)))
        } else {
            Text("Calendar access off")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }

    private var events: [CalendarItem] {
        Array(calendar.upcoming.prefix(3))
    }

    @ViewBuilder
    private var eventList: some View {
        if events.isEmpty {
            Text("No more events today")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.5))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(events) { item in
                    EventRow(item: item, color: calendar.colorFor(item))
                }
            }
        }
    }
}

struct EventRow: View {
    let item: CalendarItem
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Capsule()
                .fill(color)
                .frame(width: 3, height: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(item.isAllDay ? "All day" : Format.clockRange(start: item.start, end: item.end))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }
}

struct BatteryRow: View {
    let info: BatteryInfo

    private var tint: Color {
        if info.isCharging { return IslandColors.charging }
        return info.level <= 0.2 ? IslandColors.low : Color.white
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: BatteryGlyph.name(level: info.level, charging: info.isCharging))
                .font(.system(size: 13))
                .foregroundStyle(tint)
            Text(Format.percent(info.level))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.white)
            if info.isCharging {
                Text("Charging")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
    }
}
