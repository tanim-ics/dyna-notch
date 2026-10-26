import SwiftUI
import AppKit
import DynaNotchCore

/// Settings → Timer → Controls on hover: the compact timer row plus pause / resume, +1 min and stop buttons
/// under the notch. A click elsewhere on the island opens the panel (`IslandViewModel.tap`).
struct TimerControlsView: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var timer: TimerService

    private var isRunning: Bool { timer.state?.isRunning ?? false }
    private var canAddTime: Bool { timer.state.map { $0.mode != .stopwatch } ?? false }

    var body: some View {
        ZStack(alignment: .top) {
            // A click on the island around the buttons opens the panel.
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture { vm.tap() }
            rows
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            CompactTimerView()
                .frame(height: vm.notch.height)
                .allowsHitTesting(false)   // clicks on the time fall through to the open-panel tap
            HStack(spacing: 10) {
                control(symbol: isRunning ? "pause.fill" : "play.fill",
                        help: isRunning ? "Pause" : "Resume", id: "timerPause") {
                    TimerService.shared.toggle()
                }
                control(symbol: "plus", label: "1 min", help: "Add one minute", id: "timerAddMinute") {
                    TimerService.shared.addMinute()
                }
                .disabled(!canAddTime)
                .opacity(canAddTime ? 1 : 0.35)
                control(symbol: "stop.fill", help: "Stop", id: "timerStop", tint: Color.red.opacity(0.9)) {
                    TimerService.shared.reset()
                }
            }
            .frame(height: IslandLayout.timerControlsExtraHeight)
        }
    }

    private func control(symbol: String, label: String? = nil, help: String, id: String,
                         tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                if let label = label {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(minWidth: 34, minHeight: 24)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .uiTestID(id)
    }
}
