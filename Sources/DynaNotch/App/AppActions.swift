import AppKit
import os
import DynaNotchCore

/// One place that performs user-level actions, whatever triggered them: global shortcuts (HotKeyService), knocks
/// (KnockMonitor), the command palette and Quick Settings. Keeps those features out of the view model.
final class AppActions {
    static let shared = AppActions()

    weak var viewModel: IslandViewModel?
    /// Show On → Every display: the island on the display under the pointer (set by `IslandScreensCoordinator`).
    var activeViewModel: (() -> IslandViewModel?)?

    /// The island an action applies to: the one under the pointer, else the primary island.
    private var target: IslandViewModel? { activeViewModel?() ?? viewModel }

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "actions")

    private init() {}

    func perform(_ action: HotKeyAction) {
        logger.info("action \(action.rawValue, privacy: .public)")
        // Actions that must work without the island (or when it is broken).
        switch action {
        case .emergencyQuit:
            logger.notice("emergency quit")
            exit(0)
        case .commandPalette:
            CommandPaletteController.shared.toggle()
            return
        case .pastePlainText:
            ClipboardService.shared.pasteCurrentAsPlainText()
            return
        case .joinMeeting:
            HotKeyService.shared.joinNextMeeting()
            return
        case .openCalendar:
            HotKeyService.shared.openCalendarApp()
            return
        case .startPomodoro:
            TimerService.shared.applyConfig(AppSettings.shared.pomodoroConfig)
            TimerService.shared.startPomodoro()
            return
        case .toggleKeepAwake:
            KeepAwakeService.shared.toggle()
            return
        default:
            break
        }
        guard let vm = target else { return }
        switch action {
        case .togglePanel:
            vm.togglePanelFromKeyboard()
        case .clipboard:
            if AppSettings.shared.clipboardEnabled { vm.openFocused(.clipboard) }
        case .hide:
            vm.toggleUserHidden()
        default:
            break
        }
    }

    func perform(knock: KnockAction) {
        logger.info("knock action \(knock.rawValue, privacy: .public)")
        switch knock {
        case .none: break
        case .togglePanel: perform(.togglePanel)
        case .clipboard: perform(.clipboard)
        case .commandPalette: perform(.commandPalette)
        case .playPause: NowPlayingService.shared.togglePlayPause()
        case .lockScreen: ScreenLock.lock()
        case .toggleKeepAwake: perform(.toggleKeepAwake)
        case .screenshot: QuickActions.captureScreenshot()
        case .timer: target?.openFocused(.timer)
        }
    }

    /// Per-tab shortcut: opens that tab, or closes the panel when it is already showing it.
    func toggleTab(_ tab: PanelTab) {
        guard let vm = target else { return }
        if vm.presentation == .expanded && vm.visibleTab == tab {
            vm.collapse()
        } else {
            vm.openFocused(tab)
        }
    }

    /// Opens the panel on `tab` (command palette "Open Timer").
    func open(tab: PanelTab) {
        target?.openFocused(tab)
    }

    /// Opens the Settings window, optionally on one page.
    func openSettings(page: SettingsPage? = nil) {
        NotificationCenter.default.post(name: .dynaNotchOpenSettings, object: nil)
        if let page = page {
            DispatchQueue.main.async { SettingsNavigator.shared.go(page) }
        }
    }
}
