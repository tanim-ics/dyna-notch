import SwiftUI
import AppKit
import DynaNotchCore

/// One Home card by kind.
struct HomeCardView: View {
    let card: HomeCard

    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Group {
            switch card {
            case .music: MiniNowPlaying()
            case .calendar:
                MonthCalendarView()
                    .contentShape(Rectangle())
                    .onTapGesture { if settings.enabledTabs.contains(.calendar) { vm.select(.calendar) } }
            case .upNext: HomeUpNext()
            case .weather: HomeWeatherBlock()
            case .timer: HomeTimerStatus()
            case .worldClock: WorldClockCard()
            case .network: HomeNetworkCard()
            case .batteries: BatteriesCard()
            case .sun: SunCard()
            case .links: SavedLinksCard()
            case .colors: ColorsCard()
            case .agents: CodingAgentsCard()
            case .bluetooth: BluetoothCard()
            }
        }
        .uiTestID("home.card.\(card.rawValue)")
    }
}

/// Caption + content, the common card shape.
private struct CardSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            PanelCaption(title)
            content
        }
    }
}

private struct CardNote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(PanelStyle.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - World clock

struct WorldClockCard: View {
    @EnvironmentObject var settings: AppSettings

    private var zones: [TimeZone] {
        settings.worldClocks.split(separator: ",")
            .compactMap { TimeZone(identifier: $0.trimmingCharacters(in: .whitespaces)) }
            .prefix(4).map { $0 }
    }

    var body: some View {
        CardSection("World Clock") {
            if zones.isEmpty {
                CardNote(text: "Add cities in Settings › Home")
            } else {
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(zones, id: \.identifier) { zone in
                            row(zone, now: context.date)
                        }
                    }
                }
            }
        }
    }

    private func row(_ zone: TimeZone, now: Date) -> some View {
        let city = zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
        let diff = (zone.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)) / 3600
        var formatter = Date.FormatStyle(date: .omitted, time: .shortened)
        formatter.timeZone = zone
        return HStack(spacing: 4) {
            Text(city)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
            Text(diff == 0 ? "" : (diff > 0 ? "+\(diff)h" : "\(diff)h"))
                .font(.system(size: 9))
                .foregroundStyle(PanelStyle.tertiary)
            Spacer(minLength: 2)
            Text(now.formatted(formatter))
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
    }
}

// MARK: - Network

struct HomeNetworkCard: View {
    @ObservedObject private var network = NetworkInfoService.shared
    @EnvironmentObject var system: SystemMonitorService

    var body: some View {
        CardSection("Network") {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: network.isOnline ? (network.interfaceName == "Ethernet" ? "cable.connector" : "wifi")
                                                       : "wifi.slash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(network.isOnline ? IslandColors.charging : IslandColors.low)
                    Text(network.ssid ?? network.interfaceName ?? (network.isOnline ? "Online" : "Offline"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                }
                if let ip = network.localIP {
                    Text(ip)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(PanelStyle.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Label(Format.rate(system.netIn), systemImage: "arrow.down")
                    Label(Format.rate(system.netOut), systemImage: "arrow.up")
                }
                .font(.system(size: 9.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(PanelStyle.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .onAppear {
            NetworkInfoService.shared.start()
            NetworkInfoService.shared.refresh()
            SystemSampling.acquire("homeNetwork")
        }
        .onDisappear { SystemSampling.release("homeNetwork") }
    }
}

// MARK: - Device batteries

struct BatteriesCard: View {
    @EnvironmentObject var service: DeviceBatteryService

    var body: some View {
        CardSection("Batteries") {
            if service.devices.isEmpty {
                CardNote(text: "No batteries found")
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(service.devices.prefix(4)) { device in
                        HStack(spacing: 5) {
                            Image(systemName: device.isCharging ? "bolt.fill" : device.kind.symbolName)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(device.isCharging ? IslandColors.charging : Color.white.opacity(0.7))
                                .frame(width: 14)
                            Text(device.name)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.85))
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            if let level = device.displayLevel {
                                Text("\(level)%")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(level <= 20 ? IslandColors.low : Color.white)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Sunrise & sunset

struct SunCard: View {
    @EnvironmentObject var weather: WeatherService
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        CardSection("Sunrise & Sunset") {
            if let snapshot = weather.snapshot, let rise = snapshot.sunrise, let set = snapshot.sunset {
                HStack(spacing: 12) {
                    item("sunrise.fill", rise)
                    item("sunset.fill", set)
                }
            } else {
                CardNote(text: settings.weatherEnabled ? "Waiting for weather…" : "Turn on Weather to see sun times")
            }
        }
    }

    private func item(_ symbol: String, _ date: Date) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 13))
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
    }
}

/// "☀︎ 7:12 · 18:03" line under the weather block when the forecast has sun times.
struct SunTimesLine: View {
    let snapshot: WeatherSnapshot

    var body: some View {
        if let rise = snapshot.sunrise, let set = snapshot.sunset {
            HStack(spacing: 6) {
                Label(rise.formatted(date: .omitted, time: .shortened), systemImage: "sunrise.fill")
                Label(set.formatted(date: .omitted, time: .shortened), systemImage: "sunset.fill")
            }
            .labelStyle(CompactLabelStyle())
            .font(.system(size: 9.5, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(PanelStyle.secondary)
            .lineLimit(1)
        }
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: - Saved links

struct SavedLinksCard: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var vm: IslandViewModel

    private var links: [SavedLink] { JSONList.decode(settings.savedLinks, as: SavedLink.self) }

    var body: some View {
        CardSection("Links") {
            if links.isEmpty {
                CardNote(text: "Add links in Settings › Home")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(links.prefix(4)) { link in
                        Button {
                            open(link)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "link")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(PanelStyle.today)
                                Text(link.title.isEmpty ? (URL(string: link.url)?.host ?? link.url) : link.title)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.9))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(height: 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(link.url)
                        .uiTestID("home.link.\(link.title)")
                    }
                }
            }
        }
    }

    private func open(_ link: SavedLink) {
        var text = link.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text) else { return }
        NSWorkspace.shared.open(url)
        vm.collapse()
    }
}

// MARK: - Colors

struct ColorsCard: View {
    @EnvironmentObject var colors: ColorHistory
    @State private var copied: String?

    var body: some View {
        CardSection("Colors") {
            if colors.colors.isEmpty {
                CardNote(text: "Pick a color from the ⋯ menu")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(16), spacing: 4), count: 6), alignment: .leading, spacing: 4) {
                        ForEach(colors.colors.prefix(12), id: \.self) { value in
                            Button {
                                PanelPasteboard.copy(value)
                                copied = value
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    if copied == value { copied = nil }
                                }
                            } label: {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(swatch(value))
                                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(PressableButtonStyle())
                            .help("Copy \(value)")
                        }
                    }
                    Text(copied.map { "Copied \($0)" } ?? "Click to copy")
                        .font(.system(size: 9))
                        .foregroundStyle(copied == nil ? PanelStyle.tertiary : IslandColors.charging)
                        .lineLimit(1)
                }
            }
        }
    }

    /// History entries are hex, "rgb(r, g, b)" or "hsl(h, s%, l%)".
    private func swatch(_ value: String) -> Color {
        if let hex = HexColor.color(value) { return hex }
        let numbers = value.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .compactMap(Double.init)
        if value.lowercased().hasPrefix("rgb"), numbers.count >= 3 {
            return Color(red: numbers[0] / 255, green: numbers[1] / 255, blue: numbers[2] / 255)
        }
        if value.lowercased().hasPrefix("hsl"), numbers.count >= 3 {
            let h = numbers[0] / 360, s = numbers[1] / 100, l = numbers[2] / 100
            let b = l + s * min(l, 1 - l)
            let sv = b == 0 ? 0 : 2 * (1 - l / b)
            return Color(hue: h, saturation: sv, brightness: b)
        }
        return .gray
    }
}

// MARK: - Coding agents

struct CodingAgentsCard: View {
    @ObservedObject private var service = CodingAgentsService.shared
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        CardSection("Coding Agents") {
            if service.sessions.isEmpty {
                CardNote(text: "No Claude Code or Codex session in the last 10 min")
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(service.sessions.prefix(4)) { session in
                            row(session, now: context.date)
                        }
                    }
                }
            }
        }
        .onAppear { service.start() }
    }

    private func row(_ session: CodingAgentSession, now: Date) -> some View {
        let recent = now.timeIntervalSince(session.lastActivity) < 60
        return HStack(spacing: 5) {
            Circle()
                .fill(recent ? IslandColors.charging : Color.white.opacity(0.3))
                .frame(width: 6, height: 6)
            Image(systemName: session.tool == "Codex" ? "terminal" : "sparkles")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))
            Text(PersonalInfo.project(session.project, hidden: settings.aiHidePersonalInfo))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(recent ? "now" : Format.countdown(now.timeIntervalSince(session.lastActivity)))
                .font(.system(size: 9.5))
                .monospacedDigit()
                .foregroundStyle(PanelStyle.tertiary)
        }
        .help(session.tool)
    }
}

// MARK: - Bluetooth connect

struct BluetoothCard: View {
    @ObservedObject private var service = BluetoothConnectService.shared

    var body: some View {
        CardSection("Bluetooth") {
            if service.devices.isEmpty {
                CardNote(text: "No paired devices")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(service.devices.prefix(4)) { device in
                        row(device)
                    }
                }
            }
        }
        .onAppear { service.refresh() }
    }

    private func row(_ device: PairedDevice) -> some View {
        let busy = service.busy.contains(device.id)
        return Button {
            service.toggle(device)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: device.isConnected ? "dot.radiowaves.left.and.right" : "circle.dashed")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(device.isConnected ? PanelStyle.today : PanelStyle.tertiary)
                    .frame(width: 14)
                Text(device.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(device.isConnected ? 0.95 : 0.7))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if busy {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(device.isConnected ? "Disconnect" : "Connect")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(PanelStyle.tertiary)
                }
            }
            .frame(height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .help(device.isConnected ? "Disconnect \(device.name)" : "Connect \(device.name)")
        .uiTestID("home.bt.\(device.name)")
    }
}
