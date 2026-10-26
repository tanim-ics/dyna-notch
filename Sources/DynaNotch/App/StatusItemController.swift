import AppKit
import Combine
import DynaNotchCore
import os

/// Menu-bar icon with quick actions and the debug "Simulate" submenu.
final class StatusItemController: NSObject {
    private let viewModel: IslandViewModel
    private let statusItem: NSStatusItem
    private var cancellables = Set<AnyCancellable>()
    private var keepAwakeItem: NSMenuItem?
    private var toggleItem: NSMenuItem?
    private var readouts: MenuBarReadouts?

    private static let demoTitles: [DemoActivity: String] = [
        .volume: "Volume HUD",
        .brightness: "Brightness HUD",
        .charging: "Charging",
        .lowBattery: "Low Battery",
        .airpods: "AirPods Connected",
        .focus: "Focus On",
        .calendar: "Upcoming Event",
        .peek: "Track Peek",
        .timer: "Timer (5 min)",
        .lyrics: "Lyrics Under Notch",
        .notification: "Notification",
        .download: "Download Finished",
        .camera: "Camera In Use",
        .capsLock: "Caps Lock",
    ]

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "DynaNotch")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "DynaNotch"
        }
        statusItem.menu = buildMenu()

        AppSettings.shared.$showMenuBarIcon
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                self?.statusItem.isVisible = visible
            }
            .store(in: &cancellables)

        viewModel.$isUserHidden
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hidden in self?.toggleItem?.title = hidden ? "Show DynaNotch" : "Toggle Island" }
            .store(in: &cancellables)

        KeepAwakeService.shared.$isOn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in self?.keepAwakeItem?.state = on ? .on : .off }
            .store(in: &cancellables)

        readouts = MenuBarReadouts(viewModel: viewModel)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let title = NSMenuItem(title: "DynaNotch", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(NSMenuItem.separator())

        let toggle = NSMenuItem(title: "Toggle Island", action: #selector(toggleIsland(_:)), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        toggleItem = toggle

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)

        let awake = NSMenuItem(title: "Keep Awake", action: #selector(toggleKeepAwake(_:)), keyEquivalent: "")
        awake.target = self
        menu.addItem(awake)
        keepAwakeItem = awake

        let welcome = NSMenuItem(title: "Show Welcome…", action: #selector(showWelcome(_:)), keyEquivalent: "")
        welcome.target = self
        menu.addItem(welcome)

        let simulateItem = NSMenuItem(title: "Simulate", action: nil, keyEquivalent: "")
        let simulateMenu = NSMenu(title: "Simulate")
        for demo in DemoActivity.allCases {
            let item = NSMenuItem(title: StatusItemController.demoTitles[demo] ?? demo.rawValue,
                                  action: #selector(simulate(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = demo.rawValue
            simulateMenu.addItem(item)
        }
        simulateItem.submenu = simulateMenu
        menu.addItem(simulateItem)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit DynaNotch", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func toggleIsland(_ sender: Any?) {
        if viewModel.isUserHidden {
            viewModel.toggleUserHidden()   // "Show DynaNotch" after the Hide shortcut
        } else if viewModel.presentation == .expanded {
            viewModel.collapse()
        } else {
            viewModel.expand()
        }
    }

    @objc private func showWelcome(_ sender: Any?) {
        WelcomeController.shared.show()
    }

    @objc private func toggleKeepAwake(_ sender: Any?) {
        KeepAwakeService.shared.toggle()
    }

    @objc private func openSettings(_ sender: Any?) {
        viewModel.openSettings()
    }

    @objc private func simulate(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let demo = DemoActivity(rawValue: raw) else { return }
        viewModel.simulate(demo)
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

/// Optional menu-bar readouts (each its own status item, created / removed live by its setting):
/// battery % (settings.batteryInMenuBar), Claude 5-hour block (settings.aiMenuBarReadout) and the next meeting
/// (settings.nextMeetingInMenuBar).
final class MenuBarReadouts: NSObject {
    enum Kind: String, CaseIterable { case battery, aiUsage, meeting }

    private let viewModel: IslandViewModel
    private var items: [Kind: NSStatusItem] = [:]
    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "menubar")
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
        super.init()
        let settings = AppSettings.shared
        // Any input change re-renders all visible readouts (cheap: three short strings).
        let triggers: [AnyPublisher<Void, Never>] = [
            settings.$batteryInMenuBar.map { _ in () }.eraseToAnyPublisher(),
            settings.$aiMenuBarReadout.map { _ in () }.eraseToAnyPublisher(),
            settings.$nextMeetingInMenuBar.map { _ in () }.eraseToAnyPublisher(),
            settings.$timeFormat.map { _ in () }.eraseToAnyPublisher(),
            BatteryService.shared.$info.map { _ in () }.eraseToAnyPublisher(),
            AIUsageService.shared.$claudeBlock.map { _ in () }.eraseToAnyPublisher(),
            AIUsageService.shared.$claudeMaxBlockTokens.map { _ in () }.eraseToAnyPublisher(),
            CalendarService.shared.$upcoming.map { _ in () }.eraseToAnyPublisher(),
            Timer.publish(every: 30, tolerance: 2, on: .main, in: .common).autoconnect().map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(triggers)
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.render() }
            .store(in: &cancellables)
        DispatchQueue.main.async { [weak self] in self?.render() }
    }

    /// Current readout text per visible kind (for tests / state dumps).
    var currentTitles: [String: String] {
        var out: [String: String] = [:]
        for (kind, item) in items { out[kind.rawValue] = item.button?.title ?? "" }
        return out
    }

    // MARK: Rendering

    private func render() {
        let settings = AppSettings.shared
        update(.battery, enabled: settings.batteryInMenuBar, content: batteryContent())
        if settings.aiMenuBarReadout && !settings.aiUsageEnabled {
            // The readout needs the AI usage scanner even when the tab is hidden.
            AIUsageService.shared.start()
        }
        update(.aiUsage, enabled: settings.aiMenuBarReadout, content: aiContent())
        update(.meeting, enabled: settings.nextMeetingInMenuBar, content: meetingContent())
    }

    private func update(_ kind: Kind, enabled: Bool, content: (symbol: String, title: String, tip: String)?) {
        guard enabled, let content = content else {
            if let item = items.removeValue(forKey: kind) {
                NSStatusBar.system.removeStatusItem(item)
                logger.info("readout \(kind.rawValue, privacy: .public) removed")
            }
            return
        }
        let item: NSStatusItem
        if let existing = items[kind] {
            item = existing
        } else {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(clicked(_:))
            item.button?.identifier = NSUserInterfaceItemIdentifier("readout-" + kind.rawValue)
            item.button?.imagePosition = .imageLeading
            items[kind] = item
        }
        guard let button = item.button else { return }
        let image = NSImage(systemSymbolName: content.symbol, accessibilityDescription: content.tip)
        image?.isTemplate = true
        if button.image?.accessibilityDescription != content.tip || button.image == nil { button.image = image }
        if button.title != content.title {
            logger.info("readout \(kind.rawValue, privacy: .public): \(content.title, privacy: .public)")
            button.title = content.title
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
        }
        button.toolTip = content.tip
    }

    private func batteryContent() -> (symbol: String, title: String, tip: String)? {
        guard let info = BatteryService.shared.info else { return nil }
        let percent = Int((min(max(info.level, 0), 1) * 100).rounded())
        let symbol: String
        if info.isCharging {
            symbol = "battery.100percent.bolt"
        } else {
            switch percent {
            case 88...: symbol = "battery.100percent"
            case 63..<88: symbol = "battery.75percent"
            case 38..<63: symbol = "battery.50percent"
            case 13..<38: symbol = "battery.25percent"
            default: symbol = "battery.0percent"
            }
        }
        var tip = "Battery \(percent)%"
        if info.isCharging, let m = info.minutesToFull, m > 0 { tip += " · full in " + Format.countdown(Double(m) * 60) }
        if !info.isPluggedIn, let m = info.minutesToEmpty, m > 0 { tip += " · " + Format.countdown(Double(m) * 60) + " left" }
        return (symbol, "\(percent)%", tip)
    }

    private func aiContent() -> (symbol: String, title: String, tip: String)? {
        let service = AIUsageService.shared
        guard let block = service.claudeBlock else { return ("sparkles", "–", "Claude Code: no active 5-hour block") }
        let tokens = block.usage.total
        let left = Format.countdown(block.end.timeIntervalSinceNow)
        if service.claudeMaxBlockTokens > 0, tokens <= service.claudeMaxBlockTokens {
            let percent = Int((Double(tokens) / Double(service.claudeMaxBlockTokens) * 100).rounded())
            return ("sparkles", "\(percent)%",
                    "Claude Code 5-hour block: \(Format.tokens(tokens)) tokens, \(percent)% of your largest block · resets in \(left)")
        }
        return ("sparkles", Format.tokens(tokens), "Claude Code 5-hour block: \(Format.tokens(tokens)) tokens · resets in \(left)")
    }

    private func meetingContent() -> (symbol: String, title: String, tip: String)? {
        let now = Date()
        guard let event = CalendarService.shared.upcoming.first(where: {
            !$0.isAllDay && $0.end > now && $0.start.timeIntervalSince(now) < 12 * 3600
        }) else { return nil }
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        let when = event.start <= now ? "now" : Format.relativeMinutes(minutes)
        var title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { title = "Event" }
        if title.count > 24 { title = String(title.prefix(23)) + "…" }
        return ("calendar", "\(title) · \(when)", "\(event.title) — \(when)")
    }

    // MARK: Clicks

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let raw = sender.identifier?.rawValue.replacingOccurrences(of: "readout-", with: ""),
              let kind = Kind(rawValue: raw) else { return }
        switch kind {
        case .battery:
            viewModel.open(tab: .home)
        case .aiUsage:
            viewModel.open(tab: .aiUsage)
        case .meeting:
            if let url = CalendarService.shared.nextMeetingURL() {
                NSWorkspace.shared.open(url)
            } else {
                viewModel.open(tab: .calendar)
            }
        }
    }
}
