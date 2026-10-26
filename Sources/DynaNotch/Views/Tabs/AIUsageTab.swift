import SwiftUI
import AppKit
import DynaNotchCore

/// AI usage: Claude Code token blocks and Codex rate limits, read from local logs.
struct AIUsageTab: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 8) {
                AIUsageHeader(now: context.date)
                HStack(alignment: .top, spacing: 8) {
                    ClaudeUsageCard(now: context.date)
                    CodexUsageCard(now: context.date)
                }
            }
        }
    }
}

struct AIUsageHeader: View {
    let now: Date

    @EnvironmentObject var usage: AIUsageService

    var body: some View {
        HStack(spacing: 8) {
            Text("AI Usage")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
            if let updated = usage.lastUpdated {
                Text("Updated \(Format.countdown(now.timeIntervalSince(updated))) ago")
                    .font(.system(size: 10))
                    .foregroundStyle(PanelStyle.tertiary)
            }
            Spacer(minLength: 4)
            PanelIconButton(symbol: "arrow.clockwise", size: 10, frame: 20, help: "Refresh") {
                usage.refresh()
            }
        }
    }
}

struct ClaudeUsageCard: View {
    let now: Date

    @EnvironmentObject var usage: AIUsageService

    private static let tint = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 6) {
                cardTitle
                if usage.hasClaudeData {
                    blockSection
                    Spacer(minLength: 0)
                    totals
                } else {
                    Text("No Claude Code usage found. DynaNotch reads the session logs in ~/.claude/projects.")
                        .font(.system(size: 10))
                        .foregroundStyle(PanelStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var cardTitle: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ClaudeUsageCard.tint)
            Text("Claude Code")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white)
        }
    }

    @ViewBuilder
    private var blockSection: some View {
        if let block = usage.claudeBlock, block.isActive(now: now) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.tokens(block.usage.total))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                Text("tokens · \(Format.currency(block.cost))")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(PanelStyle.secondary)
                Spacer(minLength: 0)
            }
            if usage.claudeMaxBlockTokens > 0 {
                PanelBar(fraction: Double(block.usage.total) / Double(usage.claudeMaxBlockTokens),
                         color: ClaudeUsageCard.tint)
            }
            Text("5-hour block · resets in \(Format.countdown(block.end.timeIntervalSince(now)))")
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(PanelStyle.secondary)
        } else {
            Text("No active 5-hour block")
                .font(.system(size: 11))
                .foregroundStyle(PanelStyle.secondary)
        }
    }

    private var totals: some View {
        VStack(spacing: 2) {
            if let today = usage.claudeToday {
                totalRow("Today", tokens: today.usage.total, cost: today.cost)
            }
            if let week = usage.claudeWeek {
                totalRow("7 days", tokens: week.usage.total, cost: week.cost)
            }
        }
    }

    private func totalRow(_ title: String, tokens: Int, cost: Double) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(PanelStyle.secondary)
            Spacer(minLength: 4)
            Text(Format.tokens(tokens))
                .foregroundStyle(Color.white.opacity(0.9))
            Text(Format.currency(cost))
                .foregroundStyle(PanelStyle.secondary)
                .frame(minWidth: 48, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .medium))
        .monospacedDigit()
    }
}

struct CodexUsageCard: View {
    let now: Date

    @EnvironmentObject var usage: AIUsageService

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                    Text("Codex")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                if usage.hasCodexData, let limits = usage.codex {
                    if let primary = limits.primary {
                        RateWindowRow(window: primary, fallbackTitle: "Primary", now: now)
                    }
                    if let secondary = limits.secondary {
                        RateWindowRow(window: secondary, fallbackTitle: "Secondary", now: now)
                    }
                    if limits.primary == nil && limits.secondary == nil {
                        Text("No rate-limit data yet")
                            .font(.system(size: 10))
                            .foregroundStyle(PanelStyle.secondary)
                    }
                } else {
                    Text("No Codex usage found. DynaNotch reads the session logs in ~/.codex/sessions.")
                        .font(.system(size: 10))
                        .foregroundStyle(PanelStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct RateWindowRow: View {
    let window: RateWindow
    let fallbackTitle: String
    let now: Date

    /// `usedPercent` is 0…100 as reported by Codex.
    private var fraction: Double { window.usedPercent / 100 }

    private var tint: Color {
        fraction > 0.9 ? IslandColors.low : (fraction > 0.7 ? PanelStyle.timer : IslandColors.charging)
    }

    private var title: String {
        guard let minutes = window.windowMinutes, minutes > 0 else { return fallbackTitle }
        if minutes >= 10080 && minutes % 10080 == 0 { return minutes == 10080 ? "Weekly" : "\(minutes / 10080) weeks" }
        if minutes >= 1440 && minutes % 1440 == 0 { return "\(minutes / 1440)-day" }
        if minutes >= 60 { return "\(minutes / 60)-hour" }
        return "\(minutes)-min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                Spacer(minLength: 4)
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            PanelBar(fraction: fraction, color: tint)
            if let reset = window.resetsAt {
                Text("resets in \(Format.countdown(reset.timeIntervalSince(now)))")
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(PanelStyle.tertiary)
            }
        }
    }
}
