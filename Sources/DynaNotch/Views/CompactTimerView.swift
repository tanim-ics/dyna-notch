import SwiftUI
import AppKit
import DynaNotchCore

/// Compact island while a timer runs: ring left, remaining time right.
struct CompactTimerView: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var timer: TimerService

    var body: some View {
        CompactRow(notch: vm.notch,
                   side: IslandLayout.sideWidth(for: .timer, hudStyle: settings.hudStyle),
                   radii: IslandLayout.radii(for: .timer, hudStyle: settings.hudStyle)) {
            leading
        } trailing: {
            trailing
        }
    }

    @ViewBuilder
    private var leading: some View {
        if let state = timer.state {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                CompactTimerGlyph(state: state, date: context.date)
            }
            .opacity(state.isRunning ? 1 : 0.5)
        } else {
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PanelStyle.timer)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if let state = timer.state {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(state.displayTime(at: context.date))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(TimerTint.color(for: state))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .opacity(state.isRunning ? 1 : 0.5)
        } else {
            Text("0:00")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }
}

struct CompactTimerGlyph: View {
    let state: TimerState
    let date: Date

    var body: some View {
        if state.mode == .stopwatch {
            Image(systemName: "stopwatch.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PanelStyle.stopwatch)
        } else {
            ProgressRing(progress: TimerTint.ringProgress(for: state, at: date),
                         color: TimerTint.color(for: state),
                         lineWidth: 2.5)
                .frame(width: 15, height: 15)
        }
    }
}
