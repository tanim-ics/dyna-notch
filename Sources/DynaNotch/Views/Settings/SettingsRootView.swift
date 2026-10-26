import Foundation
import SwiftUI
import AppKit
import Combine
import DynaNotchCore

/// Sidebar groups (Notchy-style). `nil` title = no header.
enum SettingsGroup: Int, CaseIterable, Identifiable {
    case main, notch, media, productivity, yourMac, system

    var id: Int { rawValue }

    var title: String? {
        switch self {
        case .main: return nil
        case .notch: return "Notch"
        case .media: return "Media & Info"
        case .productivity: return "Productivity"
        case .yourMac: return "Your Mac"
        case .system: return "System"
        }
    }

    var pages: [SettingsPage] { SettingsPage.allCases.filter { $0.group == self } }
}

enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case general, appearance, behavior, popups, allTools
    case tabs, home, knock
    case nowPlaying, calendar, activity, aiUsage
    case timer, clipboard, quickSearch, files, screenshots
    case battery, connectivity, hud
    case permissions, about

    var id: String { rawValue }

    var group: SettingsGroup {
        switch self {
        case .general, .appearance, .behavior, .popups, .allTools: return .main
        case .tabs, .home, .knock: return .notch
        case .nowPlaying, .calendar, .activity, .aiUsage: return .media
        case .timer, .clipboard, .quickSearch, .files, .screenshots: return .productivity
        case .battery, .connectivity, .hud: return .yourMac
        case .permissions, .about: return .system
        }
    }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .behavior: return "Behavior"
        case .popups: return "Popups"
        case .allTools: return "All Tools"
        case .knock: return "Knock"
        case .tabs: return "Tabs"
        case .home: return "Home"
        case .nowPlaying: return "Now Playing"
        case .calendar: return "Calendar"
        case .activity: return "Activity"
        case .aiUsage: return "AI Usage"
        case .timer: return "Timer"
        case .clipboard: return "Clipboard"
        case .quickSearch: return "Quick Search"
        case .files: return "Files & Utilities"
        case .screenshots: return "Screenshots"
        case .battery: return "Battery"
        case .connectivity: return "Connectivity"
        case .hud: return "HUD"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .behavior: return "cursorarrow.motionlines"
        case .popups: return "bell.badge.fill"
        case .allTools: return "square.grid.3x3.fill"
        case .knock: return "hand.tap.fill"
        case .tabs: return "square.grid.2x2.fill"
        case .home: return "house.fill"
        case .nowPlaying: return "music.note"
        case .calendar: return "calendar"
        case .activity: return "chart.bar.fill"
        case .aiUsage: return "sparkles"
        case .timer: return "timer"
        case .clipboard: return "doc.on.clipboard.fill"
        case .quickSearch: return "magnifyingglass"
        case .files: return "folder.fill"
        case .screenshots: return "camera.viewfinder"
        case .battery: return "battery.75percent"
        case .connectivity: return "antenna.radiowaves.left.and.right"
        case .hud: return "speaker.wave.2.fill"
        case .permissions: return "hand.raised.fill"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .appearance: return .blue
        case .behavior: return .indigo
        case .popups: return .red
        case .allTools: return .teal
        case .knock: return .pink
        case .tabs: return .purple
        case .home: return .orange
        case .nowPlaying: return .pink
        case .calendar: return .red
        case .activity: return .green
        case .aiUsage: return .purple
        case .timer: return .orange
        case .clipboard: return .teal
        case .quickSearch: return .blue
        case .files: return .cyan
        case .screenshots: return .mint
        case .battery: return .green
        case .connectivity: return .blue
        case .hud: return .gray
        case .permissions: return .blue
        case .about: return .gray
        }
    }

    /// One plain-English sentence shown under the page title.
    var subtitle: String {
        switch self {
        case .general: return "Startup, clock and recovery, plus suggestions to get the most out of DynaNotch."
        case .appearance: return "How the island and its panel look: surfaces, shape and motion."
        case .behavior: return "When the island opens, closes and hides, and how you interact with it."
        case .popups: return "Which short popups appear under the notch, how long they stay and how they sound."
        case .allTools: return "Every DynaNotch feature in one place: switch tools on or off, or open their settings."
        case .knock: return "Tap a modifier key once, twice or three times to run an action."
        case .tabs: return "Choose and order the panel's tabs and the buttons in its header."
        case .home: return "The Home tab's card grid, world clocks, saved links, weather and colour tools."
        case .nowPlaying: return "Music in the notch: compact player, artwork, visualiser and synced lyrics."
        case .calendar: return "Upcoming events in the panel, alerts before they start and meeting reminders."
        case .activity: return "Time spent in each app today, tracked privately on this Mac."
        case .aiUsage: return "Claude Code and Codex usage read from local logs, and notifications from scripts."
        case .timer: return "Pomodoro lengths, what happens when a timer ends, and gentle break reminders."
        case .clipboard: return "How much clipboard history to keep, how pasting works and which apps to ignore."
        case .quickSearch: return "Search engines and their shortcuts, and the apps pinned in the Launcher tab."
        case .files: return "The file shelf on the notch, download popups and mounted drives."
        case .screenshots: return "Capture an area of the screen or pick a colour from anywhere."
        case .battery: return "Your Mac's battery at a glance, and when to show charging and low-battery popups."
        case .connectivity: return "Network and data traffic, plus Bluetooth accessories: connection popups and battery alerts."
        case .hud: return "Volume and brightness popups that replace the system HUD."
        case .permissions: return "What DynaNotch may access, why it needs it, and how to grant it."
        case .about: return "Version and what's new, caches, backup of your settings, reset and uninstall."
        }
    }

    /// Words of the settings on this page, used by the sidebar search.
    var keywords: String {
        switch self {
        case .general: return "launch login startup menu bar icon time format 12 24 hour clock hello intro welcome replay restart quit force quit emergency shortcut suggestions permissions recovery automation notify shortcuts scripts url link copy example show in dynanotch"
        case .appearance: return "material preset graphite onyx carbon frost satin mist clear glass black translucency blur pill notch clock color coded levels animation calm snappy bouncy speed haptics haptic non-notch display pill size scale height adjustment offset align clock date time with activities panel width size fixed fit content maximum height compact default fill colour color custom background"
        case .behavior: return "hover expand delay collapse click gestures swipe default tab previous remember current activity idle timeout invisible display screen main follow mouse full screen fullscreen preview demo auto collapse mirroring mirror projector screen sharing privacy screenshots recordings hide media app external keyboard shortcuts hotkeys recorder global command palette emergency quit paste plain text pomodoro keep awake tab shortcuts"
        case .popups: return "notification duration volume brightness caps lock focus camera microphone privacy download notify script hud alerts feature alerts timing quiet focus do not disturb alert sounds sound chime preview edge glow"
        case .tabs: return "tabs order enable reorder hotkeys shortcuts keyboard header buttons battery output keep awake actions pin lock timer screenshot color picker mic calculator emoji launcher reminders mirror"
        case .home: return "weather city location unit celsius fahrenheit color format hex rgb hsl history calendar battery expanded cards card grid columns world clock time zones cities saved links bookmarks"
        case .allTools: return "all tools features toggle overview grid search enable disable"
        case .knock: return "knock tap modifier control option command shift double triple action palette"
        case .nowPlaying: return "music artwork visualizer glow peek track lyrics offset compact pause spotify hover peek media keys play pause skip music app auto launch opening stop track info always never desktop lyrics listening history clear default music app spotify"
        case .calendar: return "events lead time alert meeting join zoom preview access join link only meetings shortcuts hotkeys calendars hide choose menu bar next meeting"
        case .activity: return "screen time apps usage clear system monitor"
        case .aiUsage: return "claude codex tokens cost usage hook limit warnings threshold menu bar readout hide personal info session cost"
        case .timer: return "pomodoro focus break sound stopwatch countdown auto continue look away stand up drink water reminder hover controls pause stop repeat timer alarm until dismissed pomodoro only"
        case .clipboard: return "history limit clean links tracking paste click numbers ignored apps password managers auto clear stored items capture sound copy twice tracking offer clean copy paste plain text shortcut"
        case .quickSearch: return "search engine google duckduckgo bing perplexity youtube github wikipedia maps amazon translate launcher apps custom engines kagi stack overflow reddit npm hacker news chatgpt example"
        case .files: return "shelf drag files downloads drive mounted eject utilities keep retention hour day week until cleared dmg disk image install long command zsh hook terminal"
        case .screenshots: return "screenshot capture area shelf color picker save folder location record screen recording area video"
        case .battery: return "battery low threshold full charge charging power level health cycles temperature status unplug time left full charge level history range 30 days menu bar drain warnings"
        case .connectivity: return "bluetooth airpods devices accessory alerts low full connected battery wifi wi-fi network ip traffic data usage"
        case .hud: return "volume brightness media keys system hud style accessibility"
        case .permissions: return "accessibility full disk access calendar reminders camera location bluetooth privacy diagnostics copy report bug"
        case .about: return "version export import reset settings tour quit backup caches clear uninstall what's new whats new"
        }
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return true }
        let haystack = title + " " + keywords
        return q.split(separator: " ").allSatisfy { word in
            haystack.range(of: String(word), options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

/// Settings window content (hosted in an NSHostingController by SettingsWindowController).
struct SettingsRootView: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var navigator = SettingsNavigator.shared
    @State private var search: String = ""
    @State private var suggestionCount = 0

    private let poll = SettingsTicker.tick

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 800, minHeight: 580)
        .onAppear(perform: refreshSuggestions)
        .onReceive(poll) { _ in refreshSuggestions() }
    }

    private func refreshSuggestions() {
        let count = SettingsSuggestions.current(settings: settings).count
        if count != suggestionCount { suggestionCount = count }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            SettingsSearchField(text: $search)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            List(selection: $navigator.selection) {
                ForEach(SettingsGroup.allCases) { group in
                    let pages = group.pages.filter { $0.matches(search) }
                    if !pages.isEmpty {
                        if let title = group.title {
                            Section(title) { rows(pages) }
                        } else {
                            Section { rows(pages) }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if SettingsPage.allCases.allSatisfy({ !$0.matches(search) }) {
                    Text("No settings match “\(search)”")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            Divider()
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 8) {
                    SettingsIcon(symbol: "power", color: .gray)
                    Text("Quit DynaNotch")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .help("Quit DynaNotch")
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        .onChange(of: search) { _, newValue in
            let visible = SettingsPage.allCases.filter { $0.matches(newValue) }
            if let current = navigator.selection, visible.contains(current) { return }
            if let first = visible.first { navigator.selection = first }
        }
    }

    private func rows(_ pages: [SettingsPage]) -> some View {
        ForEach(pages) { page in
            HStack(spacing: 8) {
                SettingsIcon(symbol: page.symbol, color: page.color)
                Text(page.title)
                Spacer(minLength: 4)
                if page == .general && suggestionCount > 0 {
                    Text("\(suggestionCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.red))
                        .help("Suggestions waiting on the General page")
                }
            }
            .tag(page)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch navigator.selection ?? .general {
        case .general: GeneralSettingsPane()
        case .appearance: AppearanceSettingsPane()
        case .behavior: BehaviorSettingsPane()
        case .popups: PopupsSettingsPane()
        case .allTools: AllToolsSettingsPane()
        case .knock: KnockSettingsPane()
        case .tabs: TabsSettingsPane()
        case .home: HomeSettingsPane()
        case .nowPlaying: NowPlayingSettingsPane()
        case .calendar: CalendarSettingsPane()
        case .activity: ActivitySettingsPane()
        case .aiUsage: AIUsageSettingsPane()
        case .timer: TimerSettingsPane()
        case .clipboard: ClipboardSettingsPane()
        case .quickSearch: QuickSearchSettingsPane()
        case .files: FilesSettingsPane()
        case .screenshots: ScreenshotsSettingsPane()
        case .battery: BatterySettingsPane()
        case .connectivity: ConnectivitySettingsPane()
        case .hud: HUDSettingsPane()
        case .permissions: PermissionsSettingsPane()
        case .about: AboutSettingsPane()
        }
    }
}
