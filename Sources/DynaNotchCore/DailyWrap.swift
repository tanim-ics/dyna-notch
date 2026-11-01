import Foundation

/// One line of the Daily Wrap card.
public struct WrapLine: Equatable, Hashable {
    public var symbol: String
    public var text: String

    public init(symbol: String, text: String) {
        self.symbol = symbol
        self.text = text
    }
}

/// Daily Wrap (CONTRACTS §6.19): today's highlights from data DynaNotch already keeps on this Mac.
public enum DailyWrap {
    public struct Input: Equatable {
        public var screenSeconds: TimeInterval
        public var topApps: [String]
        public var pomodoros: Int
        public var songs: [String]           // "Title — Artist", one per play
        public var claudeCost: Double?
        public var commits: Int?

        public init(screenSeconds: TimeInterval = 0, topApps: [String] = [], pomodoros: Int = 0, songs: [String] = [],
                    claudeCost: Double? = nil, commits: Int? = nil) {
            self.screenSeconds = screenSeconds
            self.topApps = topApps
            self.pomodoros = pomodoros
            self.songs = songs
            self.claudeCost = claudeCost
            self.commits = commits
        }
    }

    public static func lines(_ input: Input) -> [WrapLine] {
        var lines: [WrapLine] = []
        if input.screenSeconds >= 60 {
            let apps = input.topApps.prefix(3).joined(separator: ", ")
            lines.append(WrapLine(symbol: "hourglass", text: "\(DurationText.hm(input.screenSeconds)) at the Mac"
                                    + (apps.isEmpty ? "" : " · mostly \(apps)")))
        }
        if input.pomodoros > 0 {
            lines.append(WrapLine(symbol: "timer", text: "\(input.pomodoros) Pomodoro\(input.pomodoros == 1 ? "" : "s") finished"))
        }
        if let commits = input.commits, commits > 0 {
            lines.append(WrapLine(symbol: "arrow.triangle.branch", text: "\(commits) commit\(commits == 1 ? "" : "s")"))
        }
        if let top = mostPlayed(input.songs) {
            let plays = input.songs.filter { $0 == top }.count
            lines.append(WrapLine(symbol: "music.note", text: "\(top)" + (plays > 1 ? " · played \(plays)×" : "")))
        }
        if let cost = input.claudeCost, cost >= 0.01 {
            lines.append(WrapLine(symbol: "sparkle", text: String(format: "Claude Code $%.2f", cost)))
        }
        return Array(lines.prefix(5))
    }

    static func mostPlayed(_ songs: [String]) -> String? {
        guard !songs.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        var firstIndex: [String: Int] = [:]
        for (i, s) in songs.enumerated() {
            counts[s, default: 0] += 1
            if firstIndex[s] == nil { firstIndex[s] = i }
        }
        return counts.max { a, b in a.value != b.value ? a.value < b.value : firstIndex[a.key, default: 0] > firstIndex[b.key, default: 0] }?.key
    }

    /// The next wrap at `minutes` past midnight, strictly after `date` (skipping weekends when asked).
    public static func nextDate(after date: Date, minutes: Int, weekdaysOnly: Bool, calendar: Calendar = .current) -> Date? {
        let start = calendar.startOfDay(for: date)
        for day in 0..<8 {
            guard let dayStart = calendar.date(byAdding: .day, value: day, to: start),
                  let candidate = calendar.date(byAdding: .minute, value: minutes, to: dayStart) else { continue }
            if weekdaysOnly && calendar.isDateInWeekend(candidate) { continue }
            if candidate > date { return candidate }
        }
        return nil
    }
}

public enum DurationText {
    /// "6 h 12 min", "45 min", "2 h".
    public static func hm(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }
}
