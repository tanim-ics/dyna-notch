import AppKit
import Combine
import CoreWLAN
import Darwin
import Foundation
import Network
import os
import DynaNotchCore

/// Local Wi-Fi / network facts for the Home "Network" card and Settings → Connectivity. Nothing leaves the Mac.
final class NetworkInfoService: ObservableObject {
    static let shared = NetworkInfoService()
    @Published private(set) var ssid: String?          // nil without Location permission or when not on Wi-Fi
    @Published private(set) var interfaceName: String?  // "Wi-Fi", "Ethernet"
    @Published private(set) var localIP: String?
    @Published private(set) var isOnline = true

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "network")
    private let queue = DispatchQueue(label: "com.tanim.dynanotch.network", qos: .utility)
    private var monitor: NWPathMonitor?
    private var timer: AnyCancellable?
    private var started = false
    private var lastPath: NWPath?                       // queue only

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.lastPath = path
            self?.update(path: path)
        }
        monitor.start(queue: queue)
        self.monitor = monitor
        // The SSID / address can change without a path change (roaming between networks).
        timer = Timer.publish(every: 60, tolerance: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.update(path: self.lastPath ?? self.monitor?.currentPath)
        }
    }

    // MARK: Private (queue)

    private func update(path: NWPath?) {
        let online = path.map { $0.status == .satisfied } ?? false
        var kind: String?
        var bsdName: String?
        if let path = path, online {
            if path.usesInterfaceType(.wifi) {
                kind = "Wi-Fi"
            } else if path.usesInterfaceType(.wiredEthernet) {
                kind = "Ethernet"
            } else if path.usesInterfaceType(.cellular) {
                kind = "Cellular"
            } else if path.usesInterfaceType(.loopback) {
                kind = nil
            } else {
                kind = "Other"
            }
            bsdName = path.availableInterfaces.first(where: { $0.type != .loopback })?.name
        }
        let ip = online ? NetworkInfoService.ipv4Address(preferring: bsdName) : nil
        let wifiInterface = CWWiFiClient.shared().interface()
        let ssid = (kind == "Wi-Fi") ? wifiInterface?.ssid() : nil
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.isOnline != online { self.isOnline = online }
            if self.interfaceName != kind { self.interfaceName = kind }
            if self.localIP != ip { self.localIP = ip }
            if self.ssid != ssid { self.ssid = ssid }
        }
    }

    /// First IPv4 address of `preferred` (e.g. "en0"), else of any up, non-loopback interface.
    static func ipv4Address(preferring preferred: String?) -> String? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let head = first else { return nil }
        defer { freeifaddrs(first) }
        var fallback: String?
        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            let ip = String(cString: host)
            let name = String(cString: entry.pointee.ifa_name)
            if name == preferred { return ip }
            if fallback == nil, !ip.hasPrefix("169.254.") { fallback = ip }
        }
        return fallback
    }
}

/// Per-day received / sent bytes of the physical network interfaces (`TrafficLedger`), sampled every 60 s from the
/// kernel's 64-bit interface counters, persisted in App Support (traffic.json) for 365 days.
final class TrafficService: ObservableObject {
    static let shared = TrafficService()
    @Published private(set) var ledger = TrafficLedger()

    private static let file = "traffic.json"
    private static let keepDays = 365
    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "traffic")
    private let queue = DispatchQueue(label: "com.tanim.dynanotch.traffic", qos: .utility)
    private var timer: AnyCancellable?
    private var started = false
    private var previous: [UInt16: (rx: UInt64, tx: UInt64)] = [:]   // queue only, by interface index

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        if var saved = AppDataStore.loadFile(TrafficLedger.self, file: TrafficService.file) {
            saved.prune(keepDays: TrafficService.keepDays, now: Date())
            ledger = saved
        }
        queue.async { [weak self] in self?.previous = TrafficService.counters() }   // baseline: count from now on
        timer = Timer.publish(every: 60, tolerance: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in self?.sample(now) }
    }

    func clear() {
        ledger = TrafficLedger()
        AppDataStore.saveFile(ledger, file: TrafficService.file)
    }

    // MARK: Private

    private func sample(_ now: Date) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let current = TrafficService.counters()
            var rx: UInt64 = 0, tx: UInt64 = 0
            for (index, value) in current {
                guard let old = self.previous[index] else { continue }
                // A counter that went backwards was reset (interface re-created): count nothing this round.
                if value.rx >= old.rx { rx &+= value.rx - old.rx }
                if value.tx >= old.tx { tx &+= value.tx - old.tx }
            }
            self.previous = current
            guard rx > 0 || tx > 0 else { return }
            DispatchQueue.main.async {
                var updated = self.ledger
                updated.add(received: rx, sent: tx, at: now)
                if updated.days.count > TrafficService.keepDays + 1 {
                    updated.prune(keepDays: TrafficService.keepDays, now: now)
                }
                self.ledger = updated
                AppDataStore.saveFile(updated, file: TrafficService.file)
            }
        }
    }

    /// Only physical links (Wi-Fi / Ethernet "en*", cellular "pdp_ip*"): tunnels (VPN utun, ipsec) and bridges carry
    /// the same bytes again.
    private static func isPhysical(index: UInt16) -> Bool {
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
        guard if_indextoname(UInt32(index), &name) != nil else { return false }
        let s = String(cString: name)
        return s.hasPrefix("en") || s.hasPrefix("pdp_ip")
    }

    /// 64-bit byte counters per interface index via sysctl NET_RT_IFLIST2 (getifaddrs' if_data is 32-bit and wraps).
    static func counters() -> [UInt16: (rx: UInt64, tx: UInt64)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return [:] }
        var result: [UInt16: (rx: UInt64, tx: UInt64)] = [:]
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = base.advanced(by: offset).loadUnaligned(as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = base.advanced(by: offset).loadUnaligned(as: if_msghdr2.self)
                    if message.ifm_flags & IFF_LOOPBACK == 0, isPhysical(index: message.ifm_index) {
                        result[message.ifm_index] = (message.ifm_data.ifi_ibytes, message.ifm_data.ifi_obytes)
                    }
                }
                offset += messageLength
            }
        }
        return result
    }
}
