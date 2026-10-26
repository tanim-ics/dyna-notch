import AppKit
import Combine
import CoreBluetooth
import IOKit
import os
import DynaNotchCore

/// Battery levels of the Mac and its connected Bluetooth devices, merged from three sources:
/// `system_profiler` (AirPods left/right/case, some keyboards), Apple HID accessories (IOKit `BatteryPercent`)
/// and the Bluetooth LE Battery Service (0x180F / 0x2A19) for mice and keyboards such as the MX Master.
final class DeviceBatteryService: NSObject, ObservableObject {
    static let shared = DeviceBatteryService()

    /// Mac first, then devices by name; only entries with a known level.
    @Published private(set) var devices: [DeviceBattery] = []

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "devicebattery")
    private let queue = DispatchQueue(label: "com.tanim.dynanotch.devicebattery", qos: .utility)
    private var started = false
    private var timer: AnyCancellable?
    private var bluetoothEvents: AnyCancellable?
    private var batteryInfo: AnyCancellable?

    private var profilerDevices: [DeviceBattery] = []
    private var hidDevices: [DeviceBattery] = []
    private var gattLevels: [UUID: (name: String, level: Int)] = [:]
    private var macDevice: DeviceBattery?
    private lazy var macName: String = Host.current().localizedName ?? "Mac"

    // CoreBluetooth
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var levelCharacteristics: [UUID: CBCharacteristic] = [:]
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")

    private override init() {
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true
        central = CBCentralManager(delegate: self, queue: .main)
        timer = Timer.publish(every: 60, tolerance: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
        // Devices connecting / disconnecting: look again shortly after (levels appear a moment later).
        bluetoothEvents = BluetoothService.shared.events
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
        batteryInfo = BatteryService.shared.$info
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMac() }
        refresh()
    }

    func refresh() {
        refreshMac()
        queue.async { [weak self] in
            let profiler = DeviceBatteryService.readSystemProfiler()
            let hid = DeviceBatteryService.readAppleHID()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.profilerDevices = profiler
                self.hidDevices = hid
                self.publish()
            }
        }
        scanGATT()
    }

    // MARK: Mac

    private func refreshMac() {
        guard let info = BatteryService.shared.info else {
            macDevice = nil
            publish()
            return
        }
        let smart = DeviceBatteryService.readSmartBattery()
        var parts: [String] = []
        if let health = smart.health { parts.append("Health \(Int((health * 100).rounded()))%") }
        if let cycles = smart.cycles { parts.append("\(cycles) cycles") }
        if let celsius = smart.temperature { parts.append("\(Int(celsius.rounded()))°C") }
        macDevice = DeviceBattery(id: "mac", name: macName, kind: .mac,
                                  level: Int((info.level * 100).rounded()), isCharging: info.isCharging,
                                  detail: parts.isEmpty ? nil : parts.joined(separator: " · "))
        publish()
    }

    private func publish() {
        let gatt = gattLevels.map { id, value in
            DeviceBattery(id: id.uuidString, name: value.name, kind: .other, level: value.level)
        }
        var sources: [[DeviceBattery]] = [profilerDevices, hidDevices, gatt]
        if let mac = macDevice { sources.append([mac]) }
        let merged = DeviceBatteryMerge.merge(sources).filter { $0.kind == .mac || $0.displayLevel != nil }
        if merged != devices { devices = merged }
    }

    // MARK: Sources (background queue)

    private static func readSystemProfiler() -> [DeviceBattery] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "-detailLevel", "basic", "SPBluetoothDataType"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return BluetoothProfilerParser.parse(data)
    }

    private static func readAppleHID() -> [DeviceBattery] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [DeviceBattery] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard let percent = (property("BatteryPercent") as? NSNumber)?.intValue,
                  let name = property("Product") as? String else { continue }
            let address = (property("DeviceAddress") as? String)?
                .replacingOccurrences(of: "-", with: ":").uppercased() ?? name
            result.append(DeviceBattery(id: address, name: name, kind: DeviceKind.classify(minorType: nil, name: name),
                                        level: min(100, max(0, percent))))
        }
        return result
    }

    private static func readSmartBattery() -> (health: Double?, cycles: Int?, temperature: Double?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil, nil) }
        defer { IOObjectRelease(service) }
        func int(_ key: String) -> Int? {
            (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber)?.intValue
        }
        let data = IORegistryEntryCreateCFProperty(service, "BatteryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] ?? [:]
        func nested(_ key: String) -> Int? { (data[key] as? NSNumber)?.intValue }
        let cycles = int("CycleCount") ?? nested("CycleCount")
        let maxCapacity = int("AppleRawMaxCapacity") ?? int("NominalChargeCapacity")
            ?? nested("NominalChargeCapacity") ?? nested("FullChargeCapacity")
        let design = int("DesignCapacity") ?? nested("DesignCapacity")
        var health: Double?
        if let maxCapacity = maxCapacity, let design = design, maxCapacity > 0, design > 0 {
            health = min(Double(maxCapacity) / Double(design), 1.0)
        }
        // Temperature is reported in hundredths of a degree Celsius.
        let temperature = (int("Temperature") ?? nested("Temperature") ?? int("VirtualTemperature")
            ?? nested("VirtualTemperature")).map { Double($0) / 100 }
        return (health, cycles, temperature.flatMap { $0 > 0 && $0 < 100 ? $0 : nil })
    }

    // MARK: Bluetooth LE battery service

    private func scanGATT() {
        guard let central = central, central.state == .poweredOn else { return }
        let connected = central.retrieveConnectedPeripherals(withServices: [DeviceBatteryService.batteryService])
        let ids = Set(connected.map(\.identifier))
        // Forget devices that went away.
        for id in Array(peripherals.keys) where !ids.contains(id) {
            peripherals[id] = nil
            levelCharacteristics[id] = nil
            gattLevels[id] = nil
        }
        for peripheral in connected {
            if let characteristic = levelCharacteristics[peripheral.identifier], peripheral.state == .connected {
                peripheral.readValue(for: characteristic)
                continue
            }
            peripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            if peripheral.state == .connected {
                peripheral.discoverServices([DeviceBatteryService.batteryService])
            } else {
                central.connect(peripheral, options: nil)
            }
        }
        publish()
    }
}

extension DeviceBatteryService: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            scanGATT()
        } else if central.state == .unauthorized {
            logger.info("Bluetooth not authorised; LE battery levels unavailable")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([DeviceBatteryService.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        levelCharacteristics[peripheral.identifier] = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == DeviceBatteryService.batteryService {
            peripheral.discoverCharacteristics([DeviceBatteryService.batteryLevel], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] where characteristic.uuid == DeviceBatteryService.batteryLevel {
            levelCharacteristics[peripheral.identifier] = characteristic
            peripheral.readValue(for: characteristic)
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == DeviceBatteryService.batteryLevel,
              let byte = characteristic.value?.first else { return }
        let name = peripheral.name ?? "Bluetooth Device"
        gattLevels[peripheral.identifier] = (name, min(100, Int(byte)))
        publish()
    }
}
