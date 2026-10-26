import Combine
import Darwin
import Foundation
import IOKit
import os
import DynaNotchCore

/// CPU / memory / network / disk / battery-health sampling while the System or Home tab is visible.
final class SystemMonitorService: ObservableObject {
    static let shared = SystemMonitorService()

    @Published private(set) var cpu: Double = 0
    @Published private(set) var memoryUsed: UInt64 = 0
    @Published private(set) var memoryTotal: UInt64 = 0
    @Published private(set) var netIn: Double = 0
    @Published private(set) var netOut: Double = 0
    @Published private(set) var diskFree: Int64 = 0
    @Published private(set) var diskTotal: Int64 = 0
    @Published private(set) var batteryCycles: Int?
    @Published private(set) var batteryHealth: Double?
    /// Last ~60 CPU samples (0...1), oldest first, for a sparkline.
    @Published private(set) var cpuHistory: [Double] = []

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "sysmon")
    private let historyLimit = 60
    private var timer: AnyCancellable?
    private var active = false
    private var previousTicks: CPUTicks?
    private var previousNet: (inBytes: UInt64, outBytes: UInt64, at: Date)?

    private init() {}

    func setActive(_ on: Bool) {
        let apply = { [weak self] in
            guard let self = self, on != self.active else { return }
            self.active = on
            if on {
                self.readBattery()
                self.sample()
                self.timer = Timer.publish(every: 2, on: .main, in: .common)
                    .autoconnect()
                    .sink { [weak self] _ in self?.sample() }
            } else {
                self.timer?.cancel()
                self.timer = nil
                // Rates would be meaningless across a pause.
                self.previousNet = nil
            }
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }

    // MARK: Sampling (main queue; every call is a few syscalls)

    private func sample() {
        if let ticks = SystemMonitorService.readCPUTicks() {
            if let previous = previousTicks {
                let usage = SystemMath.cpuUsage(previous: previous, current: ticks)
                cpu = usage
                var history = cpuHistory
                history.append(usage)
                if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }
                cpuHistory = history
            }
            previousTicks = ticks
        }

        let total = ProcessInfo.processInfo.physicalMemory
        if memoryTotal != total { memoryTotal = total }
        if let used = SystemMonitorService.readMemoryUsed(), memoryUsed != used { memoryUsed = used }

        let now = Date()
        if let net = SystemMonitorService.readNetworkBytes() {
            if let previous = previousNet {
                let interval = now.timeIntervalSince(previous.at)
                netIn = SystemMath.rate(previous: previous.inBytes, current: net.inBytes, interval: interval)
                netOut = SystemMath.rate(previous: previous.outBytes, current: net.outBytes, interval: interval)
            }
            previousNet = (net.inBytes, net.outBytes, now)
        }

        let root = URL(fileURLWithPath: "/")
        if let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            if let free = values.volumeAvailableCapacityForImportantUsage, diskFree != free { diskFree = free }
            if let totalCapacity = values.volumeTotalCapacity, diskTotal != Int64(totalCapacity) { diskTotal = Int64(totalCapacity) }
        }
    }

    private static func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let host = mach_host_self()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        mach_port_deallocate(mach_task_self_, host)
        guard result == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        return CPUTicks(user: UInt64(t.0), system: UInt64(t.1), idle: UInt64(t.2), nice: UInt64(t.3))
    }

    private static func readMemoryUsed() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let host = mach_host_self()
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        host_page_size(host, &pageSize)
        mach_port_deallocate(mach_task_self_, host)
        guard result == KERN_SUCCESS, pageSize > 0 else { return nil }
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return pages * UInt64(pageSize)
    }

    private static func readNetworkBytes() -> (inBytes: UInt64, outBytes: UInt64)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard let addr = entry.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK),
                  flags & IFF_LOOPBACK == 0,
                  let data = entry.pointee.ifa_data else { continue }
            let ifData = data.assumingMemoryBound(to: if_data.self).pointee
            totalIn &+= UInt64(ifData.ifi_ibytes)
            totalOut &+= UInt64(ifData.ifi_obytes)
        }
        return (totalIn, totalOut)
    }

    // MARK: Battery health (IORegistry, once per activation)

    private func readBattery() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            if batteryCycles != nil { batteryCycles = nil }
            if batteryHealth != nil { batteryHealth = nil }
            return
        }
        defer { IOObjectRelease(service) }

        func intProperty(_ key: String) -> Int? {
            guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() else { return nil }
            return (value as? NSNumber)?.intValue
        }

        // Newer macOS releases only expose some capacities inside the "BatteryData" dictionary.
        var batteryData: [String: Any] = [:]
        if let value = IORegistryEntryCreateCFProperty(service, "BatteryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue(), let dict = value as? [String: Any] {
            batteryData = dict
        }
        func nested(_ key: String) -> Int? { (batteryData[key] as? NSNumber)?.intValue }

        let cycles = intProperty("CycleCount") ?? nested("CycleCount")
        let maxCapacity = intProperty("AppleRawMaxCapacity") ?? intProperty("NominalChargeCapacity")
            ?? nested("NominalChargeCapacity") ?? nested("FullChargeCapacity")
        let design = intProperty("DesignCapacity") ?? nested("DesignCapacity")
        var health: Double?
        if let maxCapacity = maxCapacity, let design = design, maxCapacity > 0, design > 0 {
            // New batteries often report slightly above design capacity; show that as 100 %.
            health = min(Double(maxCapacity) / Double(design), 1.0)
        }
        if batteryCycles != cycles { batteryCycles = cycles }
        if batteryHealth != health { batteryHealth = health }
    }
}
