import AppKit
import Carbon.HIToolbox
import Combine
import os
import DynaNotchCore

/// Global hotkeys via Carbon `RegisterEventHotKey` (no Accessibility permission). Every binding comes from
/// `HotKeyMap.parse(settings.hotkeyBindings)` (factory defaults merged): all `HotKeyAction`s plus per-tab keys
/// ("tab.<PanelTab>"). Settings changes re-register at once. Emergency Quit is registered first and stays active
/// even with `hotkeysEnabled` off, so a broken build can always be quit from the keyboard.
final class HotKeyService: ObservableObject {
    static let shared = HotKeyService()

    /// Kept for API compatibility (v3); the actions now go through `AppActions`.
    var onTogglePanel: (() -> Void)?
    var onClipboard: (() -> Void)?

    /// Currently registered bindings: settings key → "⌃⌥N" (diagnostics, Settings read-outs).
    @Published private(set) var registered: [String: String] = [:]
    /// Keys whose registration failed (taken by another app or the system).
    @Published private(set) var failed: [String] = []
    private(set) var isSuspended = false

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var keysByID: [UInt32: String] = [:]
    private var nextID: UInt32 = 1
    private var handlerRef: EventHandlerRef?
    private var observers = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "hotkey")
    private static let signature: OSType = 0x444E4348   // "DNCH"

    private init() {}

    func start() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            DispatchQueue.main.async { HotKeyService.shared.fire(hotKeyID.id) }
            return noErr
        }
        let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, &handlerRef)
        guard status == noErr else {
            logger.error("InstallEventHandler failed: \(status)")
            return
        }
        reload()

        let settings = AppSettings.shared
        Publishers.Merge3(settings.$hotkeyBindings.map { _ in () },
                          settings.$hotkeysEnabled.map { _ in () },
                          settings.$calendarHotkeys.map { _ in () })
            .dropFirst(3)
            .debounce(for: .milliseconds(80), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.reload() }
            .store(in: &observers)
    }

    func stop() {
        observers.removeAll()
        unregisterAll()
        if let handler = handlerRef {
            RemoveEventHandler(handler)
            handlerRef = nil
        }
    }

    /// Re-registers every binding from the settings string (actions + per-tab), honouring `hotkeysEnabled`
    /// and `calendarHotkeys`. Emergency Quit goes first.
    func reload() {
        guard handlerRef != nil else { return }
        unregisterAll()
        guard !isSuspended else { return }
        let settings = AppSettings.shared
        let map = HotKeyMap.parse(settings.hotkeyBindings)

        // 1. Emergency Quit — always, even when shortcuts are off or something else is broken.
        if let quit = map.binding(for: .emergencyQuit) {
            register(key: HotKeyAction.emergencyQuit.rawValue, binding: quit)
        }
        if settings.hotkeysEnabled {
            for action in HotKeyAction.allCases where action != .emergencyQuit {
                if (action == .joinMeeting || action == .openCalendar) && !settings.calendarHotkeys { continue }
                if let binding = map.binding(for: action) { register(key: action.rawValue, binding: binding) }
            }
            for tab in PanelTab.allCases {
                let key = HotKeyMap.tabKey(tab)
                if let binding = map.binding(for: key) { register(key: key, binding: binding) }
            }
        }
        let list = registered.keys.sorted().map { "\($0)=\(registered[$0] ?? "")" }.joined(separator: " ")
        logger.info("hotkeys registered (\(self.registered.count)): \(list, privacy: .public)")
        if !failed.isEmpty {
            logger.error("hotkeys unavailable (in use elsewhere): \(self.failed.joined(separator: ","), privacy: .public)")
        }
    }

    /// The settings shortcut recorder suspends all hotkeys while it listens for keys.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        unregisterAll()
        logger.info("hotkeys suspended")
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        reload()
    }

    /// Opens the join link of the current / next meeting; nothing when there is none.
    func joinNextMeeting() {
        guard let url = CalendarService.shared.nextMeetingURL() else {
            logger.info("join meeting: no meeting with a link")
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Opens Calendar.app.
    func openCalendarApp() {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    // MARK: Private

    private func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        keysByID.removeAll()
        registered.removeAll()
        failed.removeAll()
    }

    private func register(key: String, binding: HotKeyBinding) {
        // Two actions on the same keys: the first one (emergency quit, then contract order) wins.
        if registered.values.contains(binding.display) {
            failed.append(key)
            return
        }
        var ref: EventHotKeyRef?
        let id = nextID
        nextID &+= 1
        let hotKeyID = EventHotKeyID(signature: HotKeyService.signature, id: id)
        let status = RegisterEventHotKey(binding.keyCode, binding.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref = ref {
            refs[id] = ref
            keysByID[id] = key
            registered[key] = binding.display
        } else {
            failed.append(key)
            logger.error("RegisterEventHotKey \(key, privacy: .public) \(binding.display, privacy: .public) failed: \(status)")
        }
    }

    private func fire(_ id: UInt32) {
        guard let key = keysByID[id] else { return }
        logger.info("hotkey \(key, privacy: .public)")
        if let action = HotKeyAction(rawValue: key) {
            if action == .emergencyQuit {
                AppActions.shared.perform(.emergencyQuit)
                return
            }
            guard AppSettings.shared.hotkeysEnabled else { return }
            AppActions.shared.perform(action)
        } else if key.hasPrefix("tab."), let tab = PanelTab(rawValue: String(key.dropFirst(4))) {
            guard AppSettings.shared.hotkeysEnabled else { return }
            AppActions.shared.toggleTab(tab)
        }
    }
}
