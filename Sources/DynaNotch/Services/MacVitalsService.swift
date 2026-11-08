import AppKit
import Combine
import Darwin
import Foundation
import DynaNotchCore

/// Mac Vitals (CONTRACTS §6.18): heat and memory pressure (system events), low disk (every 10 min) and an app stuck
/// at full CPU (sampled every 60 s, GUI apps only). Paused while the setting is off or nobody is at the Mac.
final class MacVitalsService {
    static let shared = MacVitalsService()

    struct Alert: Equatable {
        var title: String
        var detail: String
        var symbol: String
    }

    /// Main queue.
    let alerts = PassthroughSubject<Alert, Never>()

    private var started = false
    private var cancellables = Set<AnyCancellable>()
    private var memorySource: DispatchSourceMemoryPressure?
    private var memoryCheckPending = false
    private var diskTimer: AnyCancellable?
    private var cpuTimer: AnyCancellable?
    private var lastCPU: [Int32: (cpu: UInt64, at: Date)] = [:]
    private var runaway = RunawayTracker()
    private var lastAlert: [String: Date] = [:]
    private(set) var last = "none"
    private static let quiet: TimeInterval = 30 * 60

    private init() {}

    var state: [String: Any] { ["enabled": memorySource != nil, "last": last] }

    func start() {
        guard !started else { return }
        started = true
        AppSettings.shared.$macVitals
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in on ? self?.enable() : self?.disable() }
            .store(in: &cancellables)
    }

    /// Test hook: shows that alert now (real numbers where there are any).
    func simulate(_ kind: String) {
        switch kind {
        case "thermal": raise("thermal", Alert(title: Vitals.thermalTitle(2) ?? "Hot", detail: thermalDetail(), symbol: "thermometer.high"), force: true)
        case "memory": raise("memory", memoryAlert(critical: false), force: true)
        case "disk": raise("disk", diskAlert(), force: true)
        case "runaway": raise("runaway", Alert(title: "Finder is using a full core",
                                               detail: "For 2 minutes · click to open Activity Monitor",
                                               symbol: "cpu.fill"), force: true)
        default: break
        }
    }

    // MARK: Main queue

    private func enable() {
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.thermalChanged() }
            .store(in: &cancellables)
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in self?.memoryEvent() }
        source.resume()
        memorySource = source
        diskTimer = Timer.publish(every: 600, tolerance: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.checkDisk() }
        cpuTimer = Timer.publish(every: 60, tolerance: 10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.sampleCPU() }
        checkDisk()
    }

    private func disable() {
        memorySource?.cancel()
        memorySource = nil
        diskTimer = nil
        cpuTimer = nil
        lastCPU = [:]
        runaway = RunawayTracker()
    }

    private func raise(_ kind: String, _ alert: Alert, force: Bool = false) {
        let now = Date()
        if !force, let at = lastAlert[kind], now.timeIntervalSince(at) < MacVitalsService.quiet { return }
        lastAlert[kind] = now
        last = "\(kind): \(alert.title) · \(alert.detail)"
        alerts.send(alert)
    }

    /// The kernel event is only a hint (it also fires on short blips while pressure is green): check the system's
    /// own pressure level now and again 20 s later, and alert only if it is still raised.
    private func memoryEvent() {
        guard !memoryCheckPending, MacVitalsService.memorySeverity() > 0 else { return }
        memoryCheckPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self = self else { return }
            self.memoryCheckPending = false
            guard self.memorySource != nil else { return }
            let severity = MacVitalsService.memorySeverity()
            if severity > 0 { self.raise("memory", self.memoryAlert(critical: severity >= 2)) }
        }
    }

    private static func memorySeverity() -> Int {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return 0 }
        return Vitals.memorySeverity(pressureLevel: Int(level))
    }

    private func thermalChanged() {
        let raw = ProcessInfo.processInfo.thermalState.rawValue
        guard let title = Vitals.thermalTitle(raw) else { return }
        raise("thermal", Alert(title: title, detail: thermalDetail(), symbol: "thermometer.high"))
    }

    private func thermalDetail() -> String {
        if let top = topApp() { return "\(top) is busiest · macOS slows the Mac down to cool it" }
        return "macOS slows the Mac down to cool it"
    }

    private func memoryAlert(critical: Bool) -> Alert {
        Alert(title: critical ? "Memory is almost full" : "Memory is getting tight",
              detail: topMemoryApp().map { "\($0) uses the most · click to open Activity Monitor" } ?? "Click to open Activity Monitor",
              symbol: "memorychip.fill")
    }

    private func diskAlert() -> Alert {
        let (free, _) = diskSpace()
        return Alert(title: "Your disk is almost full", detail: "\(Vitals.gigabytes(free)) left", symbol: "internaldrive.fill")
    }

    private func diskSpace() -> (Int64, Int64) {
        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return (values?.volumeAvailableCapacityForImportantUsage ?? 0, Int64(values?.volumeTotalCapacity ?? 0))
    }

    private func checkDisk() {
        guard !UserPresence.shared.isAway else { return }
        let (free, total) = diskSpace()
        if Vitals.diskLow(free: free, total: total) { raise("disk", diskAlert()) }
    }

    // MARK: CPU

    private static func footprint(_ pid: Int32) -> UInt64? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }

    /// The regular app using the most memory (the old text named the busiest-CPU app instead).
    private func topMemoryApp() -> String? {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in MacVitalsService.footprint(app.processIdentifier).map { (app, $0) } }
            .max { $0.1 < $1.1 }?.0.localizedName
    }

    private static func cpuTime(_ pid: Int32) -> UInt64? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        guard result == 0 else { return nil }
        return info.ri_user_time + info.ri_system_time   // Apple silicon: Mach time units; scaled below
    }

    private static let timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info.denom == 0 ? 1 : Double(info.numer) / Double(info.denom)
    }()

    /// Percent of one core for each regular app since the last sample.
    private func samplePercents() -> [Int32: Double] {
        let now = Date()
        var result: [Int32: Double] = [:]
        var next: [Int32: (cpu: UInt64, at: Date)] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            guard let raw = MacVitalsService.cpuTime(pid) else { continue }
            let ns = UInt64(Double(raw) * MacVitalsService.timebase)
            if let prev = lastCPU[pid] {
                result[pid] = Vitals.cpuPercent(previous: prev.cpu, current: ns, elapsed: now.timeIntervalSince(prev.at))
            }
            next[pid] = (ns, now)
        }
        lastCPU = next
        return result
    }

    private func sampleCPU() {
        guard !UserPresence.shared.isAway else { lastCPU = [:]; return }
        for pid in runaway.update(samplePercents()) {
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "An app"
            raise("runaway-\(pid)", Alert(title: "\(name) is using a full core",
                                          detail: "For 2 minutes · click to open Activity Monitor", symbol: "cpu.fill"))
        }
    }

    /// The regular app with the most CPU since the last sample (or nil before the first one).
    private func topApp() -> String? {
        guard let (pid, percent) = samplePercents().max(by: { $0.value < $1.value }), percent > 5 else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }
}
