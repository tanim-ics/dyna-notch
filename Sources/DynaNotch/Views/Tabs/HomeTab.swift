import SwiftUI
import AppKit
import DynaNotchCore

/// Home: mini player + month calendar | weather + timer | up next.
struct HomeTab: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                MiniNowPlaying()
                MonthCalendarView()
            }
            .frame(width: 210)
            VStack(alignment: .leading, spacing: 12) {
                HomeWeatherBlock()
                HomeTimerStatus()
            }
            .frame(width: 150, alignment: .topLeading)
            HomeUpNext()
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Mini now playing

struct MiniNowPlaying: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var nowPlaying: NowPlayingService

    var body: some View {
        HStack(spacing: 8) {
            artwork
            VStack(alignment: .leading, spacing: 1) {
                Text(nowPlaying.snapshot.isEmpty ? "Nothing playing" : nowPlaying.snapshot.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(nowPlaying.snapshot.isEmpty ? "Play some music" : nowPlaying.snapshot.artist)
                    .font(.system(size: 10))
                    .foregroundStyle(PanelStyle.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !nowPlaying.snapshot.isEmpty {
                controls
            }
        }
        .frame(height: 36)
    }

    @ViewBuilder
    private var artwork: some View {
        if nowPlaying.snapshot.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .frame(width: 36, height: 36)
        } else {
            ArtworkView(image: nowPlaying.artwork,
                        size: 36,
                        style: settings.artworkStyle,
                        isPlaying: nowPlaying.snapshot.isPlaying,
                        cornerRadius: 8,
                        fallbackIcon: nowPlaying.appIcon)
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            PanelIconButton(symbol: "backward.fill", size: 10, frame: 20, tint: .white) { nowPlaying.previous() }
            PanelIconButton(symbol: nowPlaying.snapshot.isPlaying ? "pause.fill" : "play.fill",
                            size: 13, frame: 22, tint: .white) { nowPlaying.togglePlayPause() }
            PanelIconButton(symbol: "forward.fill", size: 10, frame: 20, tint: .white) { nowPlaying.next() }
        }
    }
}

// MARK: - Month calendar

struct MonthCalendarView: View {
    private struct Day: Identifiable {
        let id: Int
        let number: Int
        let inMonth: Bool
        let isToday: Bool
    }

    private let calendar = Calendar.current
    private let rowHeight: CGFloat = 14

    var body: some View {
        let now = Date()
        let days = monthDays(for: now)
        return VStack(alignment: .leading, spacing: 3) {
            Text(now, format: .dateTime.month(.wide).year())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white)
            weekdayRow
            grid(days)
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { item in
                Text(item.element)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(PanelStyle.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func grid(_ days: [Day]) -> some View {
        let rows = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        return VStack(spacing: 1) {
            ForEach(Array(rows.enumerated()), id: \.offset) { row in
                HStack(spacing: 0) {
                    ForEach(row.element) { day in
                        dayCell(day)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Day) -> some View {
        Text("\(day.number)")
            .font(.system(size: 9.5, weight: day.isToday ? .bold : .medium))
            .monospacedDigit()
            .foregroundStyle(dayColor(day))
            .frame(width: rowHeight + 1, height: rowHeight)
            .background(
                Circle()
                    .fill(day.isToday ? PanelStyle.today : Color.clear)
            )
            .frame(maxWidth: .infinity)
    }

    private func dayColor(_ day: Day) -> Color {
        if day.isToday { return .white }
        return day.inMonth ? Color.white.opacity(0.85) : Color.white.opacity(0.25)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let shift = max(0, min(6, calendar.firstWeekday - 1))
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private func monthDays(for date: Date) -> [Day] {
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let range = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let first = interval.start
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let today = calendar.component(.day, from: date)

        var previousCount = 30
        if let previous = calendar.date(byAdding: .month, value: -1, to: first),
           let prevRange = calendar.range(of: .day, in: .month, for: previous) {
            previousCount = prevRange.count
        }

        var days: [Day] = []
        var id = 0
        for i in 0..<leading {
            days.append(Day(id: id, number: previousCount - leading + 1 + i, inMonth: false, isToday: false))
            id += 1
        }
        for d in range {
            days.append(Day(id: id, number: d, inMonth: true, isToday: d == today))
            id += 1
        }
        var next = 1
        while days.count % 7 != 0 {
            days.append(Day(id: id, number: next, inMonth: false, isToday: false))
            next += 1
            id += 1
        }
        return days
    }
}

// MARK: - Weather

struct HomeWeatherBlock: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var weather: WeatherService

    var body: some View {
        if !settings.weatherEnabled {
            placeholder("Weather is off")
        } else if let snapshot = weather.snapshot {
            content(snapshot)
        } else {
            placeholder(weather.status.isEmpty ? "Loading weather…" : weather.status)
        }
    }

    private func content(_ snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: snapshot.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 20))
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int(snapshot.temperature.rounded()))°")
                        .font(.system(size: 28, weight: .semibold))
                        .monospacedDigit()
                    Text(unitLetter)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PanelStyle.secondary)
                }
                .foregroundStyle(Color.white)
            }
            Text(snapshot.summary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
            Text(detail(snapshot))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(PanelStyle.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .onTapGesture { weather.refresh() }
        .help("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)) · click to refresh")
    }

    private var unitLetter: String {
        settings.temperatureUnit.symbol.replacingOccurrences(of: "°", with: "")
    }

    private func detail(_ s: WeatherSnapshot) -> String {
        let range = "H \(Int(s.high.rounded()))° L \(Int(s.low.rounded()))°"
        return s.locationName.isEmpty ? range : "\(s.locationName) · \(range)"
    }

    private func placeholder(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "cloud.sun")
                .font(.system(size: 16))
                .foregroundStyle(Color.white.opacity(0.4))
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(PanelStyle.secondary)
                .lineLimit(2)
        }
    }
}

// MARK: - Timer status

struct HomeTimerStatus: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var timer: TimerService

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PanelCaption("Timer")
            if let state = timer.state {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    running(state, date: context.date)
                }
            } else {
                Button { vm.select(.timer) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "timer")
                            .font(.system(size: 11, weight: .semibold))
                        Text("No timer running")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(PanelStyle.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func running(_ state: TimerState, date: Date) -> some View {
        let tint = TimerTint.color(for: state)
        return HStack(spacing: 6) {
            ProgressRing(progress: TimerTint.ringProgress(for: state, at: date), color: tint, lineWidth: 2)
                .frame(width: 14, height: 14)
            Text(TimerTint.title(for: state))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(state.displayTime(at: date))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .opacity(state.isRunning ? 1 : 0.55)
        .contentShape(Rectangle())
        .onTapGesture { vm.select(.timer) }
    }
}

// MARK: - Up next

struct HomeUpNext: View {
    @EnvironmentObject var calendar: CalendarService

    private var events: [CalendarItem] { Array(calendar.upcoming.prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelCaption("Up Next")
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch calendar.access {
        case .granted:
            if events.isEmpty {
                Text("Nothing else today")
                    .font(.system(size: 11))
                    .foregroundStyle(PanelStyle.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(events) { item in
                        EventRow(item: item, color: calendar.colorFor(item))
                    }
                }
            }
        case .notDetermined:
            PanelPillButton(title: "Connect Calendar", symbol: "calendar") { calendar.requestAccess() }
        case .denied:
            Text("Calendar access off")
                .font(.system(size: 11))
                .foregroundStyle(PanelStyle.secondary)
        }
    }
}
