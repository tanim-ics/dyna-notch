import AppKit
import Combine
import DynaNotchCore

/// Menu-bar icon with quick actions and the debug "Simulate" submenu.
final class StatusItemController: NSObject {
    private let viewModel: IslandViewModel
    private let statusItem: NSStatusItem
    private var cancellables = Set<AnyCancellable>()
    private var keepAwakeItem: NSMenuItem?

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

        KeepAwakeService.shared.$isOn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in self?.keepAwakeItem?.state = on ? .on : .off }
            .store(in: &cancellables)
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

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)

        let awake = NSMenuItem(title: "Keep Awake", action: #selector(toggleKeepAwake(_:)), keyEquivalent: "")
        awake.target = self
        menu.addItem(awake)
        keepAwakeItem = awake

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
        if viewModel.presentation == .expanded {
            viewModel.collapse()
        } else {
            viewModel.expand()
        }
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
