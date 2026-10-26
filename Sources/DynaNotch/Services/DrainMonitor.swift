import AppKit
import Combine
import Darwin
import Foundation
import os
import DynaNotchCore

/// Settings → Battery → Drain warnings: while on battery, samples per-process CPU every 2 minutes and posts one
/// notification island per app that stays above 50 % CPU for ~6 minutes (three consecutive high samples).
/// Re-armed when the Mac is plugged in. Started by `BatteryService.start()`.
final class DrainMonitor {
    static let shared = DrainMonitor()

    static let interval: TimeInterval = 120
    static let cpuThreshold: Double = 50          // percent of one core
    static let samplesNeeded = 3                  // 3 × 2 min ≈ 6 min

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "drain")
    private let queue = DispatchQueue(label: "com.tanim.dynanotch.drain", qos: .utility)
    private var started = false
    private var timer: AnyCancellable?

    // Background state (queue only)
    private var lastCPU: [pid_t: UInt64] = [:]    // cumulative CPU ns per pid
    private var lastSampleAt: UInt64 = 0          // mach-continuous ns
    private var highCounts: [pid_t: Int] = [:]
    private var warnedApps = Set<String>()

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        timer = Timer.publish(every: DrainMonitor.interval, tolerance: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func tick() {
        let onBattery = BatteryService.shared.info.map { !$0.isPluggedIn } ?? false
        let enabled = AppSettings.shared.drainWarnings
        queue.async { [weak self] in
            guard let self = self else { return }
            guard enabled, onBattery else {
                self.reset(clearWarned: !onBattery)   // plugged in → re-arm every app
                return
            }
            self.sample()
        }
    }

    // MARK: Sampling (queue)

    private func reset(clearWarned: Bool) {
        lastCPU = [:]
        highCounts = [:]
        lastSampleAt = 0
        if clearWarned { warnedApps = [] }
    }

    private func sample() {
        let now = DrainMonitor.nowNanos()
        let current = DrainMonitor.cpuTimes()
        defer {
            lastCPU = current
            lastSampleAt = now
        }
        guard lastSampleAt > 0, now > lastSampleAt else { return }
        let wall = Double(now - lastSampleAt)
        var counts: [pid_t: Int] = [:]
        for (pid, cpu) in current {
            guard let previous = lastCPU[pid], cpu >= previous else { continue }
            let percent = Double(cpu - previous) / wall * 100
            guard percent > DrainMonitor.cpuThreshold else { continue }
            let count = (highCounts[pid] ?? 0) + 1
            counts[pid] = count
            if count >= DrainMonitor.samplesNeeded { warn(pid: pid, percent: percent) }
        }
        highCounts = counts
    }

    private func warn(pid: pid_t, percent: Double) {
        guard let name = DrainMonitor.appName(pid: pid), !warnedApps.contains(name) else { return }
        warnedApps.insert(name)
        logger.info("drain warning: \(name, privacy: .public) at \(Int(percent))% CPU")
        DispatchQueue.main.async {
            ScreenRecorder.notify(title: "\(name) is draining the battery",
                                  body: "\(Int(percent.rounded()))% CPU for over 6 min", symbol: "bolt.trianglebadge.exclamationmark.fill", category: .battery)
        }
    }

    // MARK: Process helpers

    /// Cumulative user + system CPU time (ns) of every process we may inspect (other users' processes fail quietly).
    static func cpuTimes() -> [pid_t: UInt64] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [:] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return [:] }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let numer = UInt64(max(timebase.numer, 1)), denom = UInt64(max(timebase.denom, 1))
        var result: [pid_t: UInt64] = [:]
        for pid in pids.prefix(count) where pid > 0 {
            var info = rusage_info_v2()
            let rc = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            guard rc == 0 else { continue }
            // ri_*_time is in mach absolute-time units (ns on Intel, ticks on Apple silicon).
            let ticks = info.ri_user_time &+ info.ri_system_time
            result[pid] = ticks.multipliedReportingOverflow(by: numer).overflow ? ticks / denom * numer : ticks * numer / denom
        }
        return result
    }

    static func appName(pid: pid_t) -> String? {
        if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName { return name }
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let name = String(cString: buffer)
        return name.isEmpty ? nil : name
    }

    private static func nowNanos() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }
}
