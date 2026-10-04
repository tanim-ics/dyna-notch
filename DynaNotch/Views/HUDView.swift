import SwiftUI

struct HUDView: View {
    let type: HUDType

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.15))
                        Capsule()
                            .fill(accentColor)
                            .frame(width: max(geo.size.width * CGFloat(value), 0))
                    }
                }
                .frame(height: 6)
                .clipShape(Capsule())
            }

            Text(percentText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 40, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private var value: Float {
        switch type {
        case .volume(let v): return min(max(v, 0), 1.0)
        case .brightness(let v): return min(max(v, 0), 1.0)
        case .battery(let v, _): return min(max(v, 0), 1.0)
        }
    }

    private var iconName: String {
        switch type {
        case .volume(let v):
            if v == 0 { return "speaker.slash.fill" }
            if v < 0.33 { return "speaker.wave.1.fill" }
            if v < 0.66 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness: return "sun.max.fill"
        case .battery(let v, let isCharging):
            if isCharging { return "bolt.fill" }
            if v < 0.2 { return "battery.25" }
            if v < 0.5 { return "battery.50" }
            if v < 0.75 { return "battery.75" }
            return "battery.100"
        }
    }

    private var label: String {
        switch type {
        case .volume: return "Volume"
        case .brightness: return "Brightness"
        case .battery(_, let isCharging): return isCharging ? "Charging" : "Battery"
        }
    }

    private var percentText: String {
        "\(Int(round(value * 100)))%"
    }

    private var accentColor: Color {
        switch type {
        case .volume: return .blue
        case .brightness: return .yellow
        case .battery(let v, let isCharging):
            if isCharging { return .green }
            return v < 0.2 ? .red : .green
        }
    }
}
