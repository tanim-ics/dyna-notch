import Foundation
import SwiftUI
import AppKit
import Combine
import DynaNotchCore
import os

// MARK: - Shortcut recording

/// One shortcut recorder listens at a time: a local key-down monitor while global hotkeys are suspended.
final class ShortcutRecordingSession: ObservableObject {
    static let shared = ShortcutRecordingSession()

    /// `HotKeyMap` key being recorded ("togglePanel", "tab.timer" …), nil when idle.
    @Published private(set) var recordingKey: String?
    /// Shown under the chip while recording (e.g. "Add ⌃, ⌥ or ⌘").
    @Published private(set) var hint: String?

    private var monitor: Any?
    private var onCapture: ((HotKeyBinding?) -> Void)?

    private init() {}

    func begin(key: String, onCapture: @escaping (HotKeyBinding?) -> Void) {
        cancel()
        recordingKey = key
        hint = nil
        self.onCapture = onCapture
        HotKeyService.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.handle(event)
        }
    }

    func cancel() {
        guard recordingKey != nil || monitor != nil else { return }
        finish()
    }

    private func finish() {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        onCapture = nil
        recordingKey = nil
        hint = nil
        HotKeyService.shared.resume()
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let code = UInt32(event.keyCode)
        let hasModifier = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
        if !hasModifier {
            if code == 53 {                       // Esc: cancel
                finish()
                return nil
            }
            if code == 51 || code == 117 {        // Delete / Forward Delete: clear
                let capture = onCapture
                finish()
                capture?(nil)
                return nil
            }
            hint = "Add ⌃, ⌥ or ⌘ — Esc cancels, Delete clears"
            return nil
        }
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= HotKeyBinding.command }
        if flags.contains(.shift) { mods |= HotKeyBinding.shift }
        if flags.contains(.option) { mods |= HotKeyBinding.option }
        if flags.contains(.control) { mods |= HotKeyBinding.control }
        let capture = onCapture
        finish()
        capture?(HotKeyBinding(keyCode: code, modifiers: mods))
        return nil
    }
}

enum ShortcutNames {
    /// Human name of a `HotKeyMap` key, for conflict warnings.
    static func title(for key: String) -> String {
        if let action = HotKeyAction(rawValue: key) { return action.title }
        if key.hasPrefix("tab."), let tab = PanelTab(rawValue: String(key.dropFirst(4))) { return "\(tab.title) tab" }
        return key
    }
}

/// Chip showing the binding; click to record. ⟲ restores the factory shortcut, ✕ clears it.
struct ShortcutRecorderChip: View {
    let key: String
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var session = ShortcutRecordingSession.shared

    private var map: HotKeyMap { HotKeyMap.parse(settings.hotkeyBindings) }
    private var binding: HotKeyBinding? { map.binding(for: key) }
    private var isDefault: Bool { binding == HotKeyMap.defaults.binding(for: key) }
    private var recording: Bool { session.recordingKey == key }
    private var testID: String { "shortcut-" + key }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if recording {
                    session.cancel()
                } else {
                    session.begin(key: key) { captured in set(captured) }
                }
            } label: {
                Text(recording ? "Type shortcut…" : (binding?.display ?? "None"))
                    .font(.system(.body, design: binding == nil && !recording ? .default : .rounded))
                    .monospacedDigit()
                    .foregroundStyle(recording ? Color.accentColor : (binding == nil ? Color.secondary : Color.primary))
                    .frame(minWidth: 96)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(recording ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(recording ? Color.accentColor : Color.clear, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .help(recording ? "Press the new shortcut. Esc cancels, Delete clears." : "Click to record a new shortcut")
            .uiTestID(testID)
            Button { reset() } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(.borderless)
                .disabled(isDefault)
                .help("Restore the default shortcut")
                .uiTestID(testID + "-reset")
            Button { set(nil) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(binding == nil)
                .help("Remove this shortcut")
                .uiTestID(testID + "-clear")
        }
        .onDisappear { if recording { session.cancel() } }
    }

    private func set(_ b: HotKeyBinding?) {
        var m = HotKeyMap.parse(settings.hotkeyBindings)
        m.bindings[key] = b
        settings.hotkeyBindings = m.serialize()
    }

    private func reset() {
        var m = HotKeyMap.parse(settings.hotkeyBindings)
        m.bindings[key] = HotKeyMap.defaults.binding(for: key)
        settings.hotkeyBindings = m.serialize()
    }
}

/// Settings row with a shortcut recorder; warns inline when another shortcut uses the same keys.
struct ShortcutRow: View {
    let key: String
    let symbol: String
    let color: Color
    let title: String
    let detail: String

    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var session = ShortcutRecordingSession.shared
    @ObservedObject private var hotkeys = HotKeyService.shared

    private var conflict: String? {
        let map = HotKeyMap.parse(settings.hotkeyBindings)
        guard let b = map.binding(for: key) else { return nil }
        return map.conflict(for: b, excluding: key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingRow(symbol: symbol, color: color, title: title, detail: detail) {
                ShortcutRecorderChip(key: key)
            }
            if session.recordingKey == key, let hint = session.hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .padding(.leading, 32)
            } else if settings.hotkeysEnabled, hotkeys.failed.contains(key) {
                Label("Taken by another app or macOS — pick different keys.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .padding(.leading, 32)
            } else if let other = conflict {
                Label("Also used by “\(ShortcutNames.title(for: other))” — only one of them will work.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .padding(.leading, 32)
            }
        }
    }
}

extension HotKeyAction {
    var settingsSymbol: String {
        switch self {
        case .togglePanel: return "rectangle.topthird.inset.filled"
        case .clipboard: return "doc.on.clipboard.fill"
        case .hide: return "eye.slash.fill"
        case .commandPalette: return "command"
        case .emergencyQuit: return "xmark.octagon.fill"
        case .joinMeeting: return "video.fill"
        case .openCalendar: return "calendar"
        case .pastePlainText: return "doc.plaintext.fill"
        case .startPomodoro: return "brain.head.profile"
        case .toggleKeepAwake: return "cup.and.saucer.fill"
        }
    }

    var settingsColor: Color {
        switch self {
        case .togglePanel: return .blue
        case .clipboard: return .teal
        case .hide: return .gray
        case .commandPalette: return .indigo
        case .emergencyQuit: return .red
        case .joinMeeting: return .green
        case .openCalendar: return .red
        case .pastePlainText: return .teal
        case .startPomodoro: return .orange
        case .toggleKeepAwake: return .brown
        }
    }

    var settingsDetail: String {
        switch self {
        case .togglePanel: return "Open or close the panel from any app."
        case .clipboard: return "Open the panel on the Clipboard tab, ready to search."
        case .hide: return "Hide the island completely; press again to bring it back."
        case .commandPalette: return "Search tabs, actions and settings from the keyboard."
        case .emergencyQuit: return "Quit DynaNotch at once if it ever gets in your way."
        case .joinMeeting: return "Open the video link of your current or next meeting."
        case .openCalendar: return "Open the Calendar app."
        case .pastePlainText: return "Paste the clipboard without formatting. Needs Accessibility."
        case .startPomodoro: return "Start a Pomodoro focus session."
        case .toggleKeepAwake: return "Keep your Mac awake, or let it sleep again."
        }
    }
}

// MARK: - Hex colour helpers

enum SettingsColorHex {
    static func color(_ hex: String) -> Color? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }

    static func hex(_ color: Color) -> String {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return "#1C1C1E" }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }
}

// MARK: - Home cards

struct HomeCardsEditor: View {
    @EnvironmentObject var settings: AppSettings

    private var enabled: [HomeCard] { HomeCard.parseList(settings.homeCards) }
    private var ordered: [HomeCard] { enabled + HomeCard.allCases.filter { !enabled.contains($0) } }

    var body: some View {
        ForEach(Array(ordered.enumerated()), id: \.element) { entry in
            let card = entry.element
            let on = enabled.contains(card)
            HStack(spacing: 10) {
                SettingsIcon(symbol: card.symbolName, color: on ? Color.orange : Color.gray, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(card.title)
                        if card.span > 1 {
                            Text("Wide")
                                .font(.caption2)
                                .foregroundStyle(Color.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                    }
                    Text(detail(card))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .opacity(on ? 1 : 0.6)
                Spacer(minLength: 8)
                Button { move(card, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless)
                    .disabled(entry.offset == 0)
                    .help("Move up")
                    .uiTestID("homeCard-\(card.rawValue)-up")
                Button { move(card, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless)
                    .disabled(entry.offset >= ordered.count - 1)
                    .help("Move down")
                    .uiTestID("homeCard-\(card.rawValue)-down")
                Toggle("", isOn: Binding(get: { on }, set: { setEnabled(card, $0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .uiTestID("homeCard-\(card.rawValue)")
            }
        }
    }

    private func detail(_ card: HomeCard) -> String {
        switch card {
        case .music: return "The mini player for what's playing."
        case .calendar: return "This month at a glance. Needs Calendar access."
        case .upNext: return "Your next few events."
        case .weather: return "Current weather. Uses the network (Open-Meteo)."
        case .timer: return "Start a timer or see the running one."
        case .worldClock: return "The time in the cities you choose below."
        case .network: return "Wi-Fi name, IP address and current traffic."
        case .batteries: return "Your Mac and Bluetooth accessories' batteries."
        case .sun: return "Today's sunrise and sunset. Uses the weather location."
        case .links: return "One-click links you save below."
        case .colors: return "Colours you picked, ready to copy."
        case .agents: return "Running Claude Code and Codex sessions."
        case .bluetooth: return "Connect your paired devices with a click."
        }
    }

    private func setEnabled(_ card: HomeCard, _ on: Bool) {
        var list = ordered.filter { $0 == card ? on : enabled.contains($0) }
        if list.isEmpty { list = [card] }
        settings.homeCards = HomeCard.serialize(list)
    }

    private func move(_ card: HomeCard, by delta: Int) {
        var all = ordered
        guard let index = all.firstIndex(of: card) else { return }
        let target = index + delta
        guard all.indices.contains(target) else { return }
        let on = Set(enabled)
        all.swapAt(index, target)
        settings.homeCards = HomeCard.serialize(all.filter { on.contains($0) })
    }
}

// MARK: - World clocks

struct WorldClocksEditor: View {
    @EnvironmentObject var settings: AppSettings
    @State private var query = ""
    @State private var adding = false

    private var ids: [String] {
        settings.worldClocks.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var matches: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let all = TimeZone.knownTimeZoneIdentifiers.filter { !ids.contains($0) }
        guard !q.isEmpty else { return Array(all.prefix(8)) }
        return Array(all.filter {
            $0.replacingOccurrences(of: "_", with: " ").range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }.prefix(8))
    }

    var body: some View {
        if ids.isEmpty {
            Text("No cities yet.").foregroundStyle(.secondary)
        }
        ForEach(ids, id: \.self) { id in
            HStack(spacing: 10) {
                Image(systemName: "globe").frame(width: 22).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(WorldClocksEditor.city(id))
                    Text(subtitle(id)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { remove(id) } label: { Image(systemName: "minus.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove")
                    .uiTestID("worldClock-remove-\(id)")
            }
        }
        if adding {
            TextField("Search cities", text: $query, prompt: Text("Search a city, e.g. Vienna"))
                .labelsHidden()
                .uiTestID("worldClock-search")
            ForEach(matches, id: \.self) { id in
                Button {
                    add(id)
                } label: {
                    HStack {
                        Text(WorldClocksEditor.city(id))
                        Text(id).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button("Done") { adding = false; query = "" }
        } else {
            Button("Add City…") { adding = true }
                .uiTestID("worldClock-add")
        }
    }

    static func city(_ id: String) -> String {
        (id.split(separator: "/").last.map(String.init) ?? id).replacingOccurrences(of: "_", with: " ")
    }

    private func subtitle(_ id: String) -> String {
        guard let tz = TimeZone(identifier: id) else { return id }
        let f = DateFormatter()
        f.timeZone = tz
        f.dateStyle = .none
        f.timeStyle = .short
        return "\(f.string(from: Date())) · \(id)"
    }

    private func add(_ id: String) {
        guard !ids.contains(id) else { return }
        settings.worldClocks = (ids + [id]).joined(separator: ",")
        query = ""
    }

    private func remove(_ id: String) {
        settings.worldClocks = ids.filter { $0 != id }.joined(separator: ",")
    }
}

// MARK: - Saved links

struct SavedLinksEditor: View {
    @EnvironmentObject var settings: AppSettings
    @State private var title = ""
    @State private var url = ""

    private var links: [SavedLink] { JSONList.decode(settings.savedLinks, as: SavedLink.self) }

    private var normalizedURL: String? {
        var s = url.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        guard let u = URL(string: s), u.host != nil else { return nil }
        return s
    }

    var body: some View {
        if links.isEmpty {
            Text("No saved links yet.").foregroundStyle(.secondary)
        }
        ForEach(links) { link in
            HStack(spacing: 10) {
                Image(systemName: "link").frame(width: 22).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(link.title)
                    Text(link.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { remove(link) } label: { Image(systemName: "minus.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove")
            }
        }
        HStack(spacing: 8) {
            TextField("Title", text: $title, prompt: Text("Title"))
                .labelsHidden()
                .frame(width: 140)
                .uiTestID("savedLink-title")
            TextField("URL", text: $url, prompt: Text("https://example.com"))
                .labelsHidden()
                .onSubmit(add)
                .uiTestID("savedLink-url")
            Button("Add", action: add)
                .disabled(normalizedURL == nil)
                .uiTestID("savedLink-add")
        }
    }

    private func add() {
        guard let u = normalizedURL else { return }
        let name = title.trimmingCharacters(in: .whitespaces)
        let display = name.isEmpty ? (URL(string: u)?.host ?? u) : name
        settings.savedLinks = JSONList.encode(links + [SavedLink(title: display, url: u)])
        title = ""
        url = ""
    }

    private func remove(_ link: SavedLink) {
        settings.savedLinks = JSONList.encode(links.filter { $0.id != link.id })
    }
}

// MARK: - Custom search engines

struct CustomEnginesEditor: View {
    @EnvironmentObject var settings: AppSettings
    @State private var name = ""
    @State private var template = ""
    @State private var shortcut = ""

    static let examples: [SearchEngine] = [
        SearchEngine(id: "kagi", name: "Kagi", shortcut: "k", template: "https://kagi.com/search?q=%@"),
        SearchEngine(id: "stackoverflow", name: "Stack Overflow", shortcut: "so",
                     template: "https://stackoverflow.com/search?q=%@", symbol: "square.stack.3d.up.fill"),
        SearchEngine(id: "reddit", name: "Reddit", shortcut: "r",
                     template: "https://www.reddit.com/search/?q=%@", symbol: "bubble.left.and.bubble.right.fill"),
        SearchEngine(id: "npm", name: "npm", shortcut: "npm",
                     template: "https://www.npmjs.com/search?q=%@", symbol: "shippingbox.fill"),
        SearchEngine(id: "hackernews", name: "Hacker News", shortcut: "hn",
                     template: "https://hn.algolia.com/?q=%@", symbol: "newspaper.fill"),
        SearchEngine(id: "chatgpt", name: "ChatGPT", shortcut: "gpt",
                     template: "https://chatgpt.com/?q=%@", symbol: "bubble.left.fill"),
    ]

    private var engines: [SearchEngine] { JSONList.decode(settings.customSearchEngines, as: SearchEngine.self) }

    private var trimmedShortcut: String { shortcut.trimmingCharacters(in: .whitespaces).lowercased() }

    private var problem: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty && template.isEmpty && shortcut.isEmpty { return nil }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the engine a name." }
        if !template.contains("%@") { return "The URL needs %@ where the search words go." }
        if URL(string: template.replacingOccurrences(of: "%@", with: "x"))?.host == nil { return "That URL doesn't look right." }
        if trimmedShortcut.isEmpty || trimmedShortcut.contains(" ") { return "Pick a one-word shortcut, e.g. “so”." }
        let taken = (QuickSearch.builtIn + engines).map { $0.shortcut.lowercased() }
        if taken.contains(trimmedShortcut) { return "“\(trimmedShortcut)” is already used by another engine." }
        return nil
    }

    private var canAdd: Bool {
        problem == nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ForEach(engines) { engine in
            HStack(spacing: 10) {
                SettingsIcon(symbol: engine.symbol, color: .blue, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(engine.name)
                    Text(engine.template).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(engine.shortcut)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
                Button { remove(engine) } label: { Image(systemName: "minus.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove")
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Name", text: $name, prompt: Text("Name"))
                    .labelsHidden()
                    .frame(width: 130)
                    .uiTestID("engine-name")
                TextField("URL", text: $template, prompt: Text("https://example.com/search?q=%@"))
                    .labelsHidden()
                    .uiTestID("engine-url")
                TextField("Shortcut", text: $shortcut, prompt: Text("ex"))
                    .labelsHidden()
                    .frame(width: 60)
                    .onSubmit(add)
                    .uiTestID("engine-shortcut")
            }
            HStack(spacing: 8) {
                Menu("Start from an Example") {
                    ForEach(CustomEnginesEditor.examples) { example in
                        Button(example.name) {
                            name = example.name
                            template = example.template
                            shortcut = example.shortcut
                        }
                    }
                }
                .fixedSize()
                .uiTestID("engine-examples")
                Spacer()
                if let problem = problem {
                    Text(problem).font(.caption).foregroundStyle(Color.orange)
                }
                Button("Add Engine", action: add)
                    .disabled(!canAdd)
                    .uiTestID("engine-add")
            }
        }
    }

    private func add() {
        guard canAdd else { return }
        let base = name.trimmingCharacters(in: .whitespaces)
        let example = CustomEnginesEditor.examples.first { $0.template == template }
        let engine = SearchEngine(id: "custom-" + UUID().uuidString.prefix(8).lowercased(), name: base,
                                  shortcut: trimmedShortcut, template: template.trimmingCharacters(in: .whitespaces),
                                  symbol: example?.symbol ?? "magnifyingglass")
        settings.customSearchEngines = JSONList.encode(engines + [engine])
        name = ""
        template = ""
        shortcut = ""
    }

    private func remove(_ engine: SearchEngine) {
        settings.customSearchEngines = JSONList.encode(engines.filter { $0.id != engine.id })
        if settings.quickSearchEngine == engine.id { settings.quickSearchEngine = "google" }
    }
}

// MARK: - Music apps

enum MusicApps {
    struct App: Identifiable, Hashable { let id: String; let name: String }

    private static let known: [(String, String)] = [
        ("com.apple.Music", "Music"), ("com.spotify.client", "Spotify"), ("com.apple.podcasts", "Podcasts"),
        ("com.tidal.desktop", "TIDAL"), ("com.deezer.deezer-desktop", "Deezer"), ("com.amazon.music", "Amazon Music"),
        ("com.coppertino.Vox", "VOX"), ("com.colliderli.iina", "IINA"), ("org.videolan.vlc", "VLC"),
        ("com.pocketcasts.mac", "Pocket Casts"), ("au.com.shiftyjelly.PocketCasts", "Pocket Casts"),
    ]

    /// Installed players (plus a YouTube Music web app if one is installed).
    static func installed() -> [App] {
        var result: [App] = []
        for (id, name) in known where NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil {
            if !result.contains(where: { $0.name == name }) { result.append(App(id: id, name: name)) }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dirs = [home.appendingPathComponent("Applications/Chrome Apps.localized"),
                    home.appendingPathComponent("Applications"),
                    home.appendingPathComponent("Applications/Edge Apps.localized"),
                    URL(fileURLWithPath: "/Applications")]
        for dir in dirs {
            guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in items where url.pathExtension == "app" && url.lastPathComponent.localizedCaseInsensitiveContains("YouTube Music") {
                if let id = Bundle(url: url)?.bundleIdentifier, !result.contains(where: { $0.id == id }) {
                    result.append(App(id: id, name: "YouTube Music"))
                }
            }
        }
        return result
    }
}
