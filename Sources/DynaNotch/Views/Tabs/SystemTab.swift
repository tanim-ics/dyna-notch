import SwiftUI
import AppKit
import DynaNotchCore

/// System stats: CPU, memory, network, disk, battery.
struct SystemTab: View {
    @EnvironmentObject var system: SystemMonitorService

    var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { system.setActive(true) }
        .onDisappear { system.setActive(false) }
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
