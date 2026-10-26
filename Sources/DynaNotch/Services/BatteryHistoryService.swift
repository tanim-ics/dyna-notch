import Foundation
import Combine
import DynaNotchCore

/// Samples the Mac battery every 5 minutes into a 30-day `BatteryHistory`
/// (persisted to App Support `battery-history.json`).
final class BatteryHistoryService: ObservableObject {
    static let shared = BatteryHistoryService()

    @Published private(set) var history = BatteryHistory()

    private static let file = "battery-history.json"
    private var started = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        if let saved = AppDataStore.loadFile(BatteryHistory.self, file: BatteryHistoryService.file) {
            history = saved
        }
    }

    func start() {
        guard !started else { return }
        started = true
        BatteryService.shared.start()
        Timer.publish(every: 300, tolerance: 20, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.sample() }
            .store(in: &cancellables)
        // Charging state changes are always recorded (BatteryHistory keeps them regardless of spacing).
        BatteryService.shared.$info
            .compactMap { $0?.isCharging }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sample() }
            .store(in: &cancellables)
        // BatteryService reads its first value synchronously in start(); sample on the next turn as well.
        DispatchQueue.main.async { [weak self] in self?.sample() }
    }

    func clear() {
        history = BatteryHistory()
        AppDataStore.saveFile(history, file: BatteryHistoryService.file)
    }

    private func sample() {
        guard let info = BatteryService.shared.info else { return }
        var updated = history
        let level = Int((info.level * 100).rounded())
        guard updated.append(BatterySample(date: Date(), level: level, charging: info.isCharging)) else { return }
        history = updated
        AppDataStore.saveFile(updated, file: BatteryHistoryService.file)
    }
}
