import AppKit
import SwiftUI
import Combine
import os
import DynaNotchCore

/// ⌃⌥K command palette — a floating, keyboard-first search field under the notch listing tabs, actions
/// (HotKeyAction / KnockAction / timers / screenshot …) and Settings pages; ↑↓ to move, ↩ to run, Esc or a click
/// outside to close. Own key-capable panel, so typing works without activating DynaNotch.
final class CommandPaletteController: NSObject, NSWindowDelegate {
    static let shared = CommandPaletteController()

    static let size = CGSize(width: 560, height: 356)

    let model = CommandPaletteModel()
    private var panel: PalettePanel?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "palette")

    private override init() {
        super.init()
    }

    var isShown: Bool { panel?.isVisible ?? false }

    /// The palette window (scripted UI tests click inside it).
    var testWindow: NSWindow? { panel }
    var testQuery: String { model.query }
    var testSelectionTitle: String { model.selected?.title ?? "" }

    func toggle() { isShown ? hide() : show() }

    /// Renders the palette's content to a PNG (scripted visual checks; the blur renders as plain dark).
    @discardableResult
    func snapshot(to url: URL) -> Bool {
        guard let view = panel?.contentView else { return false }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.reload()
        model.query = ""
        model.selection = 0
        model.lastHoverLocation = NSEvent.mouseLocation
        position(panel)
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        model.focusToken += 1
        installMonitors()
        logger.info("palette shown (\(self.model.items.count) items)")
    }

    func hide() {
        removeMonitors()
        guard let panel = panel, panel.isVisible else { return }
        panel.orderOut(nil)
        logger.info("palette hidden")
    }

    /// Scripted tests: type a query and/or press ↑ ↓ ↩ ⎋ as the keyboard would.
    func testInput(query: String?, key: String?) {
        if let query = query { model.query = query }
        switch key {
        case "down": model.move(1)
        case "up": model.move(-1)
        case "return": run(model.selected)
        case "escape": hide()
        default: break
        }
    }

    /// Hides the palette, then performs the item (so the island can take focus if the item opens it).
    func run(_ item: PaletteItem?) {
        guard let item = item else { return }
        logger.info("palette run \(item.id, privacy: .public)")
        hide()
        DispatchQueue.main.async { item.perform() }
    }

    // MARK: Window

    private func makePanel() -> PalettePanel {
        let panel = PalettePanel(contentRect: NSRect(origin: .zero, size: CommandPaletteController.size))
        panel.delegate = self
        let root = CommandPaletteView(model: model,
                                      onRun: { [weak self] item in self?.run(item) },
                                      onClose: { [weak self] in self?.hide() })
            .environmentObject(AppSettings.shared)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: CommandPaletteController.size)
        panel.contentView = hosting
        return panel
    }

    private func position(_ panel: NSPanel) {
        let settings = AppSettings.shared
        guard let screen = ScreenLocator.targetScreen(mode: settings.displayMode) ?? NSScreen.main else { return }
        let notchHeight = max(AppActions.shared.viewModel?.notch.height ?? 0, screen.safeAreaInsets.top, 24)
        let size = CommandPaletteController.size
        let frame = screen.frame
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - notchHeight - 10 - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.window === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // Global monitors only see clicks in other apps' windows: always outside the palette.
            self?.hide()
        }
    }

    private func removeMonitors() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
        clickMonitor = nil
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case 125: model.move(1); return true                        // ↓
        case 126: model.move(-1); return true                       // ↑
        case 36, 76: run(model.selected); return true               // ↩ / enter
        case 53: hide(); return true                                // ⎋
        default:
            // ⌃N / ⌃P like Spotlight lists.
            if event.modifierFlags.contains(.control), let c = event.charactersIgnoringModifiers {
                if c == "n" { model.move(1); return true }
                if c == "p" { model.move(-1); return true }
            }
            return false
        }
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

/// Borderless, transparent panel that can become key without activating the app.
final class PalettePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        title = "Command Palette"
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func cancelOperation(_ sender: Any?) {
        CommandPaletteController.shared.hide()
    }
}

// MARK: - Model

struct PaletteItem: Identifiable {
    enum Section: String {
        case tabs = "Tabs", actions = "Actions", settings = "Settings"
    }

    let id: String
    let title: String
    let symbol: String
    let section: Section
    var keywords: String = ""
    var shortcut: String = ""
    let perform: () -> Void

    /// 0 = title starts with the query, 1 = a title word starts with it, 2 = contains, 3 = keyword match, nil = no match.
    func rank(_ query: String) -> Int? {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return 0 }
        let t = title.lowercased()
        if t.hasPrefix(q) { return 0 }
        if t.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 1 }
        if t.contains(q) { return 2 }
        let haystack = [t, keywords.lowercased(), section.rawValue.lowercased()].joined(separator: " ")
        let tokens = q.split(separator: " ")
        return tokens.allSatisfy({ haystack.contains($0) }) ? 3 : nil
    }
}

final class CommandPaletteModel: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { selection = 0 } }
    }
    @Published var selection = 0
    @Published private(set) var items: [PaletteItem] = []
    /// Bumped on every show so the view re-focuses its search field.
    @Published var focusToken = 0
    /// Pointer position of the last hover selection: rows scrolling under a resting pointer must not steal the
    /// keyboard selection, only a real pointer move selects.
    var lastHoverLocation: NSPoint?

    func hover(_ index: Int) {
        let location = NSEvent.mouseLocation
        defer { lastHoverLocation = location }
        guard let last = lastHoverLocation, last != location else { return }
        selection = index
    }

    var filtered: [PaletteItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.enumerated()
            .compactMap { pair -> (Int, Int, PaletteItem)? in
                guard let r = pair.element.rank(q) else { return nil }
                return (r, pair.offset, pair.element)
            }
            .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
            .map { $0.2 }
    }

    var selected: PaletteItem? {
        let list = filtered
        guard !list.isEmpty else { return nil }
        return list[min(max(0, selection), list.count - 1)]
    }

    func move(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selection = (min(max(0, selection), count - 1) + delta + count) % count
    }

    func reload() {
        items = CommandPaletteModel.buildItems()
    }

    private static func buildItems() -> [PaletteItem] {
        let settings = AppSettings.shared
        let keys = HotKeyMap.parse(settings.hotkeyBindings)
        let actions = AppActions.shared
        var list: [PaletteItem] = []

        // Tabs
        for tab in settings.enabledTabs {
            list.append(PaletteItem(id: "tab.\(tab.rawValue)", title: "Open \(tab.title)", symbol: tab.symbolName,
                                    section: .tabs, keywords: "tab show panel",
                                    shortcut: keys.binding(for: HotKeyMap.tabKey(tab))?.display ?? "") {
                actions.open(tab: tab)
            })
        }

        // Actions with a global shortcut
        let hotKeySymbols: [HotKeyAction: String] = [
            .togglePanel: "rectangle.topthird.inset.filled", .clipboard: "doc.on.clipboard", .hide: "eye.slash",
            .emergencyQuit: "power", .joinMeeting: "video.fill", .openCalendar: "calendar",
            .pastePlainText: "doc.plaintext", .startPomodoro: "timer", .toggleKeepAwake: "cup.and.saucer.fill",
        ]
        for action in HotKeyAction.allCases where action != .commandPalette {
            if (action == .joinMeeting || action == .openCalendar) && !settings.calendarEnabled { continue }
            if action == .clipboard && !settings.clipboardEnabled { continue }
            let title = action == .emergencyQuit ? "Quit DynaNotch" : action.title
            list.append(PaletteItem(id: "action.\(action.rawValue)", title: title,
                                    symbol: hotKeySymbols[action] ?? "command", section: .actions,
                                    keywords: action == .emergencyQuit ? "exit emergency" : "",
                                    shortcut: keys.binding(for: action)?.display ?? "") {
                actions.perform(action)
            })
        }

        // Knock actions not covered above
        list.append(PaletteItem(id: "knock.playPause", title: KnockAction.playPause.title, symbol: "playpause.fill",
                                section: .actions, keywords: "music media play pause") {
            actions.perform(knock: .playPause)
        })
        list.append(PaletteItem(id: "knock.lockScreen", title: KnockAction.lockScreen.title, symbol: "lock.fill",
                                section: .actions, keywords: "lock") {
            actions.perform(knock: .lockScreen)
        })

        // Timers, captures and toggles
        list.append(PaletteItem(id: "timer.stopwatch", title: "Start Stopwatch", symbol: "stopwatch",
                                section: .actions, keywords: "timer") {
            TimerService.shared.startStopwatch()
            actions.open(tab: .timer)
        })
        for minutes in [5, 10, 25] {
            list.append(PaletteItem(id: "timer.\(minutes)", title: "Start \(minutes)-Minute Timer", symbol: "timer",
                                    section: .actions, keywords: "countdown timer") {
                TimerService.shared.startCountdown(minutes: Double(minutes), label: "\(minutes) min")
            })
        }
        list.append(PaletteItem(id: "timer.reset", title: "Stop Timer", symbol: "stop.fill", section: .actions,
                                keywords: "timer reset cancel") {
            TimerService.shared.reset()
        })
        list.append(PaletteItem(id: "screenshot", title: "Capture Screenshot", symbol: "camera.viewfinder",
                                section: .actions, keywords: "screen capture area") {
            QuickActions.captureScreenshot()
        })
        list.append(PaletteItem(id: "colorPicker", title: "Pick a Color", symbol: "eyedropper",
                                section: .actions, keywords: "colour sampler hex") {
            QuickActions.pickColor()
        })
        list.append(PaletteItem(id: "mic", title: "Mute / Unmute Microphone", symbol: "mic.slash.fill",
                                section: .actions, keywords: "microphone input") {
            AudioDeviceService.shared.toggleMicMute()
        })
        for hours in [1, 2] {
            list.append(PaletteItem(id: "keepAwake.\(hours)h", title: "Keep Awake for \(hours) h",
                                    symbol: "cup.and.saucer.fill", section: .actions, keywords: "caffeine sleep") {
                KeepAwakeService.shared.keepAwake(for: TimeInterval(hours) * 3600)
            })
        }
        list.append(PaletteItem(id: "pin", title: "Pin / Unpin Panel", symbol: "pin.fill", section: .actions,
                                keywords: "keep open") {
            guard let vm = actions.viewModel else { return }
            vm.togglePin()
            if vm.isPinned { vm.expand() }
        })

        // Settings pages
        list.append(PaletteItem(id: "settings", title: "Open Settings", symbol: "gearshape.fill", section: .settings,
                                keywords: "preferences") {
            actions.openSettings()
        })
        for page in SettingsPage.allCases {
            list.append(PaletteItem(id: "settings.\(page.rawValue)", title: "Settings › \(page.title)",
                                    symbol: page.symbol, section: .settings, keywords: "preferences \(page.rawValue)") {
                actions.openSettings(page: page)
            })
        }
        return list
    }
}

// MARK: - View

struct CommandPaletteView: View {
    @ObservedObject var model: CommandPaletteModel
    let onRun: (PaletteItem) -> Void
    let onClose: () -> Void

    @SwiftUI.FocusState private var fieldFocused: Bool

    var body: some View {
        let list = model.filtered
        VStack(spacing: 0) {
            searchField
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
            if list.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                    Text("No matches")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { entry in
                                row(entry.element, index: entry.offset, selected: entry.offset == clamped(list.count))
                                    .id(entry.element.id)
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: model.selection) {
                        if let item = model.selected {
                            withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(item.id) }
                        }
                    }
                }
            }
            footer
        }
        .frame(width: CommandPaletteController.size.width, height: CommandPaletteController.size.height)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow)
                Color.black.opacity(0.62)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
        )
        .environment(\.colorScheme, .dark)
        .onAppear { focusField() }
        .onChange(of: model.focusToken) { focusField() }
    }

    private func clamped(_ count: Int) -> Int { min(max(0, model.selection), max(0, count - 1)) }

    private func focusField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { fieldFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "command")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
            TextField("Search tabs, actions and settings", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.white)
                .focused($fieldFocused)
                .onSubmit { if let item = model.selected { onRun(item) } }
                .uiTestID("paletteField")
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .uiTestID("paletteClear")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }

    private func row(_ item: PaletteItem, index: Int, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.1)))
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white)
                .lineLimit(1)
            Spacer(minLength: 8)
            if !item.shortcut.isEmpty {
                Text(item.shortcut)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.08)))
            }
            Text(item.section.rawValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.35))
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Color.white.opacity(0.14) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onRun(item) }
        .onHover { inside in if inside { model.hover(index) } }
        .uiTestID("paletteRow.\(item.id)")
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↑↓", "Move")
            hint("↩", "Run")
            hint("esc", "Close")
            Spacer()
            Text("⌃⌥K")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(Color.white.opacity(0.04))
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.white.opacity(0.6))
            Text(label).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.35))
        }
    }
}
