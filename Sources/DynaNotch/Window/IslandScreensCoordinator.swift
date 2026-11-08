import AppKit
import Combine
import DynaNotchCore
import os

/// Show On → Every display (CONTRACTS §6.10): keeps one extra island per display besides the primary one, rebuilt when
/// displays change or Show On changes. Extra islands have their own view model, so each hovers and opens on its own;
/// hiding DynaNotch hides them all.
final class IslandScreensCoordinator {
    private let primary: IslandViewModel
    private let primaryController: IslandWindowController
    private let settings = AppSettings.shared
    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "screens")

    private struct Extra {
        let viewModel: IslandViewModel
        let controller: IslandWindowController
        let hiddenSync: AnyCancellable
    }
    private var extras: [CGDirectDisplayID: Extra] = [:]
    private var primaryHiddenSync: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private var primaryMoveObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var settleWork: DispatchWorkItem?

    init(primary: IslandViewModel, primaryController: IslandWindowController) {
        self.primary = primary
        self.primaryController = primaryController
    }

    deinit {
        if let observer = screenObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = primaryMoveObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func start() {
        settings.$displayMode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)   // let the primary island move first
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
        settings.$hiddenDisplays
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // The primary island may have to move off a display that was just switched off.
                self.primaryController.repositionNow()
                self.rebuild()
            }
            .store(in: &cancellables)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.rebuild() }
            self?.rebuildWhenSettled()
        }
        primaryMoveObserver = NotificationCenter.default.addObserver(
            forName: IslandWindowController.primaryDisplayChanged, object: primaryController, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.rebuild() }
        }
        // After sleep or a cable re-plug displays can come back a moment after the change notification.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuildWhenSettled()
        }
        primaryHiddenSync = primary.$isUserHidden
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hidden in self?.syncHidden(hidden, from: self?.primary) }
        AppActions.shared.activeViewModel = { [weak self] in self?.islandUnderPointer() }
    }

    /// Extra islands for state.json: display name, presentation, shape and whether the panel is on screen.
    var extraStates: [[String: Any]] {
        extras.values.map { extra in
            [
                "screen": extra.controller.screenName,
                "presentation": String(describing: extra.viewModel.presentation),
                "isPill": extra.viewModel.isPill,
                "isUserHidden": extra.viewModel.isUserHidden,
                "visible": extra.controller.testWindow.isVisible,
            ]
        }
    }

    /// View models of the extra islands (URL hooks that post to every island).
    var extraViewModels: [IslandViewModel] { extras.values.map(\.viewModel) }

    /// First extra island (`dynanotch://snapshot-extra/<name>`).
    var firstExtraController: IslandWindowController? {
        extras.keys.sorted().first.flatMap { extras[$0]?.controller }
    }

    // MARK: Private (main queue)

    /// One more rebuild once the display configuration has settled (coalesced).
    private func rebuildWhenSettled() {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.primaryController.repositionNow()
            self?.rebuild()
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func rebuild() {
        let all = NSScreen.screens.compactMap(ScreenLocator.keyed)
        let wanted = settings.displayMode.extraDisplays(all: all, primary: primaryController.currentDisplayID,
                                                        hidden: DisplaySelection.parse(settings.hiddenDisplays))
        for (id, extra) in extras where !wanted.contains(id) {
            extra.controller.tearDown()
            extras[id] = nil
        }
        for id in wanted where extras[id] == nil {
            let vm = IslandViewModel(isPrimary: false)
            let controller = IslandWindowController(viewModel: vm, pinnedDisplay: id)
            controller.show()
            vm.start()
            if primary.isUserHidden { vm.toggleUserHidden() }
            let sync = vm.$isUserHidden
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak vm] hidden in self?.syncHidden(hidden, from: vm) }
            extras[id] = Extra(viewModel: vm, controller: controller, hiddenSync: sync)
        }
        logger.info("islands: primary + \(self.extras.count, privacy: .public) extra")
    }

    /// Hide DynaNotch applies to every island, whichever one it was triggered on.
    private func syncHidden(_ hidden: Bool, from source: IslandViewModel?) {
        let all = [primary] + extras.values.map(\.viewModel)
        for vm in all where vm !== source && vm.isUserHidden != hidden {
            vm.toggleUserHidden()
        }
    }

    private func islandUnderPointer() -> IslandViewModel? {
        guard !extras.isEmpty, let screen = ScreenLocator.screenContainingMouse(),
              let id = ScreenLocator.displayID(screen) else { return nil }
        return extras[id]?.viewModel
    }
}
