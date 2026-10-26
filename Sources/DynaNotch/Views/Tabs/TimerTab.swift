import SwiftUI
import AppKit
import DynaNotchCore

/// Timer: countdown presets, Pomodoro and stopwatch.
struct TimerTab: View {
    @EnvironmentObject var timer: TimerService

    var body: some View {
        ZStack(alignment: .top) {
            if let state = timer.state {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    TimerRunningView(state: state, date: context.date)
                }
            } else {
                TimerSetupView()
            }
            if timer.isAlarmRinging {
                TimerAlarmBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: timer.isAlarmRinging)
    }
}

/// "Time's up" banner with a Stop button while a repeating alarm rings (settings.repeatAlarm).
struct TimerAlarmBanner: View {
    @EnvironmentObject var timer: TimerService

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.and.waves.left.and.right.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PanelStyle.timer)
            Text("Time's up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
            Spacer(minLength: 8)
            PanelPillButton(title: "Stop Alarm", symbol: "stop.fill", tint: IslandColors.low.opacity(0.85)) {
                timer.stopAlarm()
            }
            .uiTestID("timer.stopAlarm")
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.16)))
    }
}

// MARK: - Setup

enum TimerSetupMode: String, CaseIterable {
    case standard, pomodoro, stopwatch

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .pomodoro: return "Pomodoro"
        case .stopwatch: return "Stopwatch"
        }
    }
}

struct TimerSetupView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var mode: TimerSetupMode = .standard

    /// settings.pomodoroOnly hides Standard and Stopwatch.
    private var shownMode: TimerSetupMode { settings.pomodoroOnly ? .pomodoro : mode }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                if !settings.pomodoroOnly {
                    TimerModePicker(selection: $mode)
                }
                PomodoroOnlyToggle()
            }
            Group {
                switch shownMode {
                case .standard: StandardTimerSetup()
                case .pomodoro: PomodoroSetup()
                case .stopwatch: StopwatchSetup()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct TimerModePicker: View {
    @Binding var selection: TimerSetupMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TimerSetupMode.allCases, id: \.self) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selection == mode ? Color.white : PanelStyle.secondary)
                        .frame(width: 84, height: 22)
                        .background(Capsule().fill(Color.white.opacity(selection == mode ? 0.16 : 0)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .animation(.easeInOut(duration: 0.15), value: selection)
    }
}

/// Small chip toggling settings.pomodoroOnly (same setting as Settings → Timer).
struct PomodoroOnlyToggle: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        TimerOptionChip(title: settings.pomodoroOnly ? "Pomodoro only" : "Only Pomodoro",
                        symbol: "leaf.fill", isOn: settings.pomodoroOnly) {
            settings.pomodoroOnly.toggle()
        }
        .uiTestID("timer.pomodoroOnly")
        .help(settings.pomodoroOnly ? "Show Standard and Stopwatch again" : "Hide Standard and Stopwatch")
    }
}

/// Capsule on/off chip used for timer options.
struct TimerOptionChip: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? Color.white : PanelStyle.secondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(isOn ? PanelStyle.timer.opacity(0.55) : Color.white.opacity(0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct StandardTimerSetup: View {
    @EnvironmentObject var timer: TimerService
    @EnvironmentObject var settings: AppSettings
    @State private var customMinutes: Int = 15

    private let presets: [Int] = [1, 2, 3, 5, 10, 25]

    var body: some View {
        VStack(spacing: 10) {
            Text("Set a Timer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
            HStack(spacing: 10) {
                ForEach(presets, id: \.self) { minutes in
                    presetButton(minutes)
                }
                Divider()
                    .frame(height: 30)
                    .overlay(Color.white.opacity(0.12))
                customStepper
            }
            TimerOptionChip(title: settings.repeatTimer ? "Repeats" : "Repeat", symbol: "repeat",
                            isOn: settings.repeatTimer) {
                settings.repeatTimer.toggle()
            }
            .uiTestID("timer.repeat")
            .help("Start the same timer again when it finishes")
        }
    }

    private func presetButton(_ minutes: Int) -> some View {
        Button {
            timer.startCountdown(minutes: Double(minutes), label: "\(minutes) min")
        } label: {
            VStack(spacing: 0) {
                Text("\(minutes)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("min")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(PanelStyle.secondary)
            }
            .foregroundStyle(Color.white)
            .frame(width: 40, height: 40)
            .background(Circle().fill(Color.white.opacity(0.1)))
            .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var customStepper: some View {
        HStack(spacing: 4) {
            PanelIconButton(symbol: "minus", size: 10, frame: 20) {
                customMinutes = max(1, customMinutes - (customMinutes > 10 ? 5 : 1))
            }
            Text("\(customMinutes)m")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .frame(width: 38)
            PanelIconButton(symbol: "plus", size: 10, frame: 20) {
                customMinutes = min(180, customMinutes + (customMinutes >= 10 ? 5 : 1))
            }
            PanelIconButton(symbol: "play.fill", size: 11, frame: 26, tint: PanelStyle.timer, help: "Start") {
                timer.startCountdown(minutes: Double(customMinutes), label: "\(customMinutes) min")
            }
        }
    }
}

struct PomodoroSetup: View {
    @EnvironmentObject var timer: TimerService
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                phaseInfo("Focus", minutes: settings.pomodoroWorkMinutes, color: PanelStyle.timer)
                phaseInfo("Short Break", minutes: settings.pomodoroShortBreakMinutes, color: PanelStyle.breakTime)
                phaseInfo("Long Break", minutes: settings.pomodoroLongBreakMinutes, color: PanelStyle.breakTime)
            }
            Text("Long break after \(settings.pomodoroCycles) sessions")
                .font(.system(size: 10))
                .foregroundStyle(PanelStyle.secondary)
            HStack(spacing: 14) {
                PanelPillButton(title: "Start Focus", symbol: "play.fill", tint: PanelStyle.timer.opacity(0.8)) {
                    timer.applyConfig(settings.pomodoroConfig)
                    timer.startPomodoro()
                }
                PomodoroStatsRow()
            }
        }
    }

    private func phaseInfo(_ title: String, minutes: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(minutes)")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(PanelStyle.secondary)
        }
    }
}

struct StopwatchSetup: View {
    @EnvironmentObject var timer: TimerService

    var body: some View {
        VStack(spacing: 10) {
            Text("0:00")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.4))
            PanelPillButton(title: "Start Stopwatch", symbol: "play.fill", tint: PanelStyle.stopwatch.opacity(0.8)) {
                timer.startStopwatch()
            }
        }
    }
}

// MARK: - Running

struct TimerRunningView: View {
    let state: TimerState
    let date: Date

    @EnvironmentObject var timer: TimerService
    @EnvironmentObject var settings: AppSettings

    private var tint: Color { TimerTint.color(for: state) }

    var body: some View {
        HStack(spacing: 28) {
            ring
            VStack(alignment: .leading, spacing: 10) {
                header
                if state.mode == .pomodoro {
                    sessionDots
                    PomodoroStatsRow()
                }
                controls
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var ring: some View {
        ZStack {
            ProgressRing(progress: TimerTint.ringProgress(for: state, at: date), color: tint, lineWidth: 6)
                .animation(.linear(duration: 1), value: date)
            VStack(spacing: 0) {
                Text(state.displayTime(at: date))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !state.isRunning {
                    Text("Paused")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PanelStyle.secondary)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(width: 140, height: 140)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(modeTitle.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(tint)
            Text(TimerTint.title(for: state))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
    }

    private var modeTitle: String {
        switch state.mode {
        case .countdown: return "Timer"
        case .pomodoro: return "Pomodoro"
        case .stopwatch: return "Stopwatch"
        }
    }

    private var sessionDots: some View {
        let cycles = max(1, timer.engine.config.cyclesBeforeLongBreak)
        let done = state.completedWorkSessions % cycles
        return HStack(spacing: 5) {
            ForEach(0..<cycles, id: \.self) { index in
                Circle()
                    .fill(index < done ? PanelStyle.timer : Color.white.opacity(0.18))
                    .frame(width: 7, height: 7)
            }
            Text("\(state.completedWorkSessions) done")
                .font(.system(size: 10))
                .foregroundStyle(PanelStyle.secondary)
                .padding(.leading, 4)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            PanelPillButton(title: state.isRunning ? "Pause" : "Resume",
                            symbol: state.isRunning ? "pause.fill" : "play.fill",
                            tint: tint.opacity(0.75)) {
                timer.toggle()
            }
            PanelPillButton(title: "Reset", symbol: "arrow.counterclockwise") {
                timer.reset()
            }
            if state.mode != .stopwatch {
                PanelPillButton(title: "+1 min", symbol: "plus") {
                    timer.addMinute()
                }
            }
            if state.mode == .pomodoro {
                PanelPillButton(title: "Skip", symbol: "forward.end.fill") {
                    timer.skipPhase()
                }
            }
            if state.mode == .countdown {
                TimerOptionChip(title: "Repeat", symbol: "repeat", isOn: settings.repeatTimer) {
                    settings.repeatTimer.toggle()
                }
                .uiTestID("timer.repeatRunning")
            }
        }
    }
}

/// Today · streak · total focus sessions (PomodoroStatsService).
struct PomodoroStatsRow: View {
    @EnvironmentObject var statsService: PomodoroStatsService

    var body: some View {
        let stats = statsService.stats
        let now = Date()
        HStack(spacing: 12) {
            stat(symbol: "checkmark.circle.fill", value: stats.today(now: now), label: "today", color: PanelStyle.timer)
            stat(symbol: "flame.fill", value: stats.streak(now: now), label: stats.streak(now: now) == 1 ? "day streak" : "days streak",
                 color: Color.orange)
            stat(symbol: "sum", value: stats.total, label: "total", color: PanelStyle.secondary)
        }
        .help("Completed focus sessions")
    }

    private func stat(symbol: String, value: Int, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
            Text("\(value)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(PanelStyle.secondary)
        }
        .lineLimit(1)
    }
}
