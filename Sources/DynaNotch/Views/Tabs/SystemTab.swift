import SwiftUI
import AppKit
import DynaNotchCore

/// System stats (CPU, memory, network, disk, battery), Screen Time and battery history, picked from a side rail.
struct SystemTab: View {
    @EnvironmentObject var system: SystemMonitorService
    @AppStorage("dn.data.systemSection") private var sectionRaw: String = SystemSection.overview.rawValue

    private var section: SystemSection { SystemSection(rawValue: sectionRaw) ?? .overview }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            SystemSectionRail(selection: Binding(get: { section }, set: { sectionRaw = $0.rawValue }))
            Group {
                switch section {
                case .overview: overview
                case .screenTime: ScreenTimeSection()
                case .battery: BatteryHistorySection()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { SystemSampling.acquire("systemTab") }
        .onDisappear { SystemSampling.release("systemTab") }
    }

    private var overview: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                CPUCard()
                MemoryCard()
            }
            HStack(spacing: 8) {
                NetworkCard()
                DiskCard()
                BatteryHealthCard()
            }
        }
    }
}

enum SystemSection: String, CaseIterable {
    case overview, screenTime, battery

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .screenTime: return "Screen Time"
        case .battery: return "Battery History"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.50percent"
        case .screenTime: return "hourglass"
        case .battery: return "chart.xyaxis.line"
        }
    }
}

/// Vertical icon rail (keeps the full panel height for content).
struct SystemSectionRail: View {
    @Binding var selection: SystemSection

    var body: some View {
        VStack(spacing: 4) {
            ForEach(SystemSection.allCases, id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selection == item ? Color.white : PanelStyle.secondary)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(selection == item ? 0.16 : 0))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.title)
            }
            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.15), value: selection)
    }
}

// MARK: - Screen Time

struct ScreenTimeSection: View {
    @EnvironmentObject var screenTime: ScreenTimeService
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var vm: IslandViewModel

    var body: some View {
        if !settings.screenTimeEnabled {
            VStack(spacing: 8) {
                PanelEmptyState(symbol: "hourglass", title: "Screen Time is off",
                                detail: "Turn it on in Settings to see time per app (stays on this Mac)")
                PanelPillButton(title: "Open Settings", symbol: "gearshape") { vm.openSettings() }
            }
        } else {
            let apps = screenTime.today(limit: 5)
            HStack(alignment: .top, spacing: 8) {
                PanelCard {
                    VStack(alignment: .leading, spacing: 4) {
                        PanelCaption("Today")
                        Text(Format.countdown(screenTime.totalToday()))
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("Active time in apps")
                            .font(.system(size: 10))
                            .foregroundStyle(PanelStyle.secondary)
                        Spacer(minLength: 0)
                        Text("Pauses while idle, asleep or locked")
                            .font(.system(size: 9))
                            .foregroundStyle(PanelStyle.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: 150)
                PanelCard {
                    if apps.isEmpty {
                        PanelEmptyState(symbol: "hourglass.bottomhalf.filled", title: "No usage recorded yet")
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            PanelCaption("Most used")
                            ForEach(apps) { usage in
                                ScreenTimeRow(usage: usage, maxSeconds: apps.first?.seconds ?? 1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }
}

struct ScreenTimeRow: View {
    let usage: AppUsage
    let maxSeconds: TimeInterval

    @EnvironmentObject var screenTime: ScreenTimeService

    var body: some View {
        HStack(spacing: 7) {
            Group {
                if let icon = screenTime.icon(for: usage.bundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(PanelStyle.tertiary)
                }
            }
            .frame(width: 16, height: 16)
            Text(usage.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)
            PanelBar(fraction: maxSeconds > 0 ? usage.seconds / maxSeconds : 0, color: PanelStyle.stopwatch, height: 5)
            Text(Format.countdown(usage.seconds))
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(PanelStyle.secondary)
                .frame(width: 52, alignment: .trailing)
        }
        .frame(height: 16)
    }
}

// MARK: - Battery history

enum BatteryHistoryRange: String, CaseIterable {
    case day, week, month

    var title: String {
        switch self {
        case .day: return "24 h"
        case .week: return "7 d"
        case .month: return "30 d"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        }
    }
}

struct BatteryHistorySection: View {
    @EnvironmentObject var history: BatteryHistoryService
    @EnvironmentObject var battery: BatteryService
    @AppStorage("dn.data.batteryHistoryRange") private var rangeRaw: String = BatteryHistoryRange.day.rawValue

    private var range: BatteryHistoryRange { BatteryHistoryRange(rawValue: rangeRaw) ?? .day }

    var body: some View {
        let now = Date()
        let start = now.addingTimeInterval(-range.seconds)
        let samples = history.history.samples(since: start)
        PanelCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PanelStyle.tertiary)
                    PanelCaption("Battery history")
                    if let summary = summary(samples) {
                        Text(summary)
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(PanelStyle.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    rangePicker
                }
                if samples.count < 2 {
                    PanelEmptyState(symbol: "battery.50percent",
                                    title: battery.info == nil ? "No battery" : "Collecting battery history…",
                                    detail: battery.info == nil ? nil : "A sample is taken every few minutes")
                } else {
                    BatteryHistoryChart(samples: samples, start: start, end: now, range: range)
                }
            }
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 2) {
            ForEach(BatteryHistoryRange.allCases, id: \.self) { item in
                Button {
                    rangeRaw = item.rawValue
                } label: {
                    Text(item.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(range == item ? Color.white : PanelStyle.secondary)
                        .frame(width: 38, height: 18)
                        .background(Capsule().fill(Color.white.opacity(range == item ? 0.16 : 0)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func summary(_ samples: [BatterySample]) -> String? {
        guard let low = samples.map(\.level).min(), let high = samples.map(\.level).max() else { return nil }
        return "\(low)% – \(high)%"
    }
}

/// Level line over time with charging periods shaded green. Plain Paths (no Charts dependency).
struct BatteryHistoryChart: View {
    let samples: [BatterySample]
    let start: Date
    let end: Date
    let range: BatteryHistoryRange

    /// Gaps longer than this break the line (Mac asleep / app not running).
    private var gapThreshold: TimeInterval { range == .day ? 30 * 60 : (range == .month ? 12 * 3600 : 3 * 3600) }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .trailing) {
                axisLabel("100%")
                Spacer()
                axisLabel("50%")
                Spacer()
                axisLabel("0%")
            }
            .frame(width: 28)
            VStack(spacing: 2) {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        grid(size: geo.size)
                        ForEach(Array(chargingSpans().enumerated()), id: \.offset) { entry in
                            let span = entry.element
                            Rectangle()
                                .fill(IslandColors.charging.opacity(0.14))
                                .frame(width: max(1, x(span.1, geo.size) - x(span.0, geo.size)), height: geo.size.height)
                                .offset(x: x(span.0, geo.size))
                        }
                        ForEach(Array(segments().enumerated()), id: \.offset) { entry in
                            fill(entry.element, size: geo.size)
                                .fill(LinearGradient(colors: [lineColor.opacity(0.3), lineColor.opacity(0)],
                                                     startPoint: .top, endPoint: .bottom))
                            line(entry.element, size: geo.size)
                                .stroke(lineColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
                xAxis
            }
        }
    }

    private var lineColor: Color {
        let level = samples.last?.level ?? 100
        return level <= 20 ? IslandColors.low : IslandColors.charging
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8))
            .monospacedDigit()
            .foregroundStyle(PanelStyle.tertiary)
    }

    private var xAxis: some View {
        HStack {
            ForEach(Array(ticks().enumerated()), id: \.offset) { entry in
                if entry.offset > 0 { Spacer(minLength: 0) }
                axisLabel(entry.element)
            }
        }
    }

    private func ticks() -> [String] {
        let count = range == .day ? 5 : 8
        let span = end.timeIntervalSince(start)
        return (0..<count).map { i in
            let date = start.addingTimeInterval(span * Double(i) / Double(count - 1))
            if range == .day {
                return i == count - 1 ? "Now" : date.formatted(date: .omitted, time: .shortened)
            }
            if range == .month {
                return i == count - 1 ? "Today" : date.formatted(.dateTime.day().month(.abbreviated))
            }
            return i == count - 1 ? "Today" : date.formatted(.dateTime.weekday(.abbreviated))
        }
    }

    private func grid(size: CGSize) -> some View {
        Path { path in
            for fraction in [0.0, 0.5, 1.0] {
                let y = size.height * CGFloat(fraction)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
    }

    private func x(_ date: Date, _ size: CGSize) -> CGFloat {
        let span = max(1, end.timeIntervalSince(start))
        return CGFloat(max(0, min(1, date.timeIntervalSince(start) / span))) * size.width
    }

    private func point(_ sample: BatterySample, _ size: CGSize) -> CGPoint {
        let level = CGFloat(max(0, min(100, sample.level))) / 100
        return CGPoint(x: x(sample.date, size), y: size.height - level * size.height)
    }

    /// Continuous runs of samples (split at gaps).
    private func segments() -> [[BatterySample]] {
        var result: [[BatterySample]] = []
        var current: [BatterySample] = []
        for sample in samples {
            if let last = current.last, sample.date.timeIntervalSince(last.date) > gapThreshold {
                result.append(current)
                current = []
            }
            current.append(sample)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func chargingSpans() -> [(Date, Date)] {
        var spans: [(Date, Date)] = []
        var spanStart: Date?
        var previous: BatterySample?
        for sample in samples {
            if let p = previous, sample.date.timeIntervalSince(p.date) > gapThreshold, let s = spanStart {
                spans.append((s, p.date))
                spanStart = nil
            }
            if sample.charging {
                if spanStart == nil { spanStart = sample.date }
            } else if let s = spanStart {
                spans.append((s, sample.date))
                spanStart = nil
            }
            previous = sample
        }
        if let s = spanStart, let last = samples.last { spans.append((s, last.date)) }
        return spans
    }

    private func line(_ run: [BatterySample], size: CGSize) -> Path {
        Path { path in
            for (index, sample) in run.enumerated() {
                let p = point(sample, size)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        }
    }

    private func fill(_ run: [BatterySample], size: CGSize) -> Path {
        var path = line(run, size: size)
        guard let first = run.first, let last = run.last else { return path }
        path.addLine(to: CGPoint(x: x(last.date, size), y: size.height))
        path.addLine(to: CGPoint(x: x(first.date, size), y: size.height))
        path.closeSubpath()
        return path
    }
}

/// Title + big value layout shared by the stat cards.
struct StatHeader: View {
    let symbol: String
    let title: String
    let value: String
    var tint: Color = .white

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(PanelStyle.tertiary)
            PanelCaption(title)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

struct CPUCard: View {
    @EnvironmentObject var system: SystemMonitorService

    private var tint: Color {
        system.cpu > 0.85 ? IslandColors.low : (system.cpu > 0.6 ? PanelStyle.timer : PanelStyle.stopwatch)
    }

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 6) {
                StatHeader(symbol: "cpu", title: "CPU", value: Format.percent(system.cpu))
                Sparkline(values: system.cpuHistory, color: tint)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            if values.count > 1 {
                ZStack {
                    fillPath(in: geo.size)
                        .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                    linePath(in: geo.size)
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private func point(_ index: Int, size: CGSize) -> CGPoint {
        let step = size.width / CGFloat(max(1, values.count - 1))
        let v = CGFloat(max(0, min(1, values[index])))
        return CGPoint(x: CGFloat(index) * step, y: size.height - v * size.height)
    }

    private func linePath(in size: CGSize) -> Path {
        Path { path in
            for index in values.indices {
                let p = point(index, size: size)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        }
    }

    private func fillPath(in size: CGSize) -> Path {
        var path = linePath(in: size)
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }
}

struct MemoryCard: View {
    @EnvironmentObject var system: SystemMonitorService

    private var fraction: Double {
        system.memoryTotal > 0 ? Double(system.memoryUsed) / Double(system.memoryTotal) : 0
    }

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 8) {
                StatHeader(symbol: "memorychip", title: "Memory", value: Format.percent(fraction))
                PanelBar(fraction: fraction, color: fraction > 0.85 ? IslandColors.low : Color.purple, height: 6)
                Text("\(Format.bytes(Double(system.memoryUsed))) of \(Format.bytes(Double(system.memoryTotal)))")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(PanelStyle.secondary)
            }
        }
    }
}

struct NetworkCard: View {
    @EnvironmentObject var system: SystemMonitorService

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "network")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PanelStyle.tertiary)
                    PanelCaption("Network")
                }
                rateRow(symbol: "arrow.down", value: system.netIn, color: IslandColors.charging)
                rateRow(symbol: "arrow.up", value: system.netOut, color: PanelStyle.stopwatch)
            }
        }
    }

    private func rateRow(symbol: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
            Text(Format.rate(value))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

struct DiskCard: View {
    @EnvironmentObject var system: SystemMonitorService

    private var usedFraction: Double {
        system.diskTotal > 0 ? Double(system.diskTotal - system.diskFree) / Double(system.diskTotal) : 0
    }

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 7) {
                StatHeader(symbol: "internaldrive", title: "Disk", value: Format.percent(usedFraction))
                PanelBar(fraction: usedFraction, color: usedFraction > 0.9 ? IslandColors.low : Color.teal, height: 5)
                Text("\(Format.bytes(Double(system.diskFree))) free of \(Format.bytes(Double(system.diskTotal)))")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(PanelStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

struct BatteryHealthCard: View {
    @EnvironmentObject var system: SystemMonitorService
    @EnvironmentObject var battery: BatteryService

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: batterySymbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PanelStyle.tertiary)
                    PanelCaption("Battery")
                    Spacer(minLength: 4)
                    if let info = battery.info {
                        Text(Format.percent(info.level))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                    }
                }
                detailRows
            }
        }
    }

    private var batterySymbol: String {
        guard let info = battery.info else { return "battery.100percent" }
        return BatteryGlyph.name(level: info.level, charging: info.isCharging)
    }

    @ViewBuilder
    private var detailRows: some View {
        if system.batteryCycles == nil && system.batteryHealth == nil {
            Text(battery.info == nil ? "No battery" : "Health unavailable")
                .font(.system(size: 10))
                .foregroundStyle(PanelStyle.secondary)
        } else {
            if let health = system.batteryHealth {
                detail("Health", Format.percent(health))
            }
            if let cycles = system.batteryCycles {
                detail("Cycles", "\(cycles)")
            }
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(PanelStyle.secondary)
            Spacer(minLength: 4)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .font(.system(size: 10, weight: .medium))
    }
}
