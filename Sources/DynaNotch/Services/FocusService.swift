import Combine
import Foundation
import os
import DynaNotchCore

/// Best-effort Focus (Do Not Disturb) state from ~/Library/DoNotDisturb/DB/*.json.
/// Reading those files needs Full Disk Access; `isReadable` reports whether it works.
final class FocusService: ObservableObject {
    static let shared = FocusService()

    @Published private(set) var state: FocusState = .inactive
    @Published private(set) var isReadable: Bool = false

    let changes = PassthroughSubject<FocusState, Never>()

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "focus")
    private let workQueue = DispatchQueue(label: "com.tanim.dynanotch.focus", qos: .utility)
    private let assertionsURL: URL
    private let configurationsURL: URL

    private var started = false
    private var hasInitialReading = false
    private var evaluating = false
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []

    private init() {
        let db = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
        assertionsURL = db.appendingPathComponent("Assertions.json")
        configurationsURL = db.appendingPathComponent("ModeConfigurations.json")
    }

    func start() {
        guard !started else { return }
        started = true

        Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)

        let center = DistributedNotificationCenter.default()
        let names = [
            "com.apple.donotdisturb.state.changed",
            "_NSDoNotDisturbEnabledNotification",
            "_NSDoNotDisturbDisabledNotification",
        ]
        for name in names {
            let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: OperationQueue.main) { [weak self] _ in
                // The JSON files are written slightly after the notification.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.evaluate() }
            }
            observers.append(token)
        }
        evaluate()
    }

    // MARK: Private

    private func evaluate() {
        guard !evaluating else { return }
        evaluating = true
        let assertionsURL = self.assertionsURL
        let configurationsURL = self.configurationsURL
        workQueue.async { [weak self] in
            var readable = false
            var newState = FocusState.inactive
            let fm = FileManager.default
            if fm.isReadableFile(atPath: assertionsURL.path),
               let assertions = try? Data(contentsOf: assertionsURL) {
                readable = true
                let configurations = try? Data(contentsOf: configurationsURL)
                newState = FocusParser.state(assertionsJSON: assertions, configurationsJSON: configurations)
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.evaluating = false
                self.apply(state: newState, readable: readable)
            }
        }
    }

    private func apply(state newState: FocusState, readable: Bool) {
        if isReadable != readable { isReadable = readable }
        guard readable else { return }
        guard hasInitialReading else {
            hasInitialReading = true
            if state != newState { state = newState }
            return
        }
        guard newState != state else { return }
        state = newState
        let name = newState.name
        let onOff: String = newState.isActive ? "on" : "off"
        logger.info("focus changed: \(name, privacy: .public) (\(onOff, privacy: .public))")
        changes.send(newState)
    }
}
