import Combine
import Foundation
import IOBluetooth
import os
import DynaNotchCore

/// Bluetooth connect / disconnect events (AirPods, headphones, keyboards …) via IOBluetooth user notifications.
/// Notifications are delivered on the main run loop.
final class BluetoothService: NSObject {
    static let shared = BluetoothService()

    let events = PassthroughSubject<BluetoothEvent, Never>()

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "bluetooth")
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var startedAt = Date.distantPast
    private static let startupGrace: TimeInterval = 3.0
    private static let batteryKeys = ["batteryPercentSingle", "batteryPercentCombined", "batteryPercentCase"]

    private override init() {
        super.init()
    }

    func start() {
        guard connectNotification == nil else { return }
        startedAt = Date()
        // Also fires once for every device that is already connected.
        let note: IOBluetoothUserNotification? = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        connectNotification = note
        if note == nil {
            logger.error("IOBluetooth connect notification registration failed")
        }
    }

    // MARK: IOBluetooth callbacks

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = BluetoothService.address(of: device)
        let alreadyKnown = disconnectNotifications[address] != nil
        if !alreadyKnown {
            let disconnect: IOBluetoothUserNotification? = device.register(
                forDisconnectNotification: self,
                selector: #selector(deviceDisconnected(_:device:))
            )
            if let disconnect = disconnect {
                disconnectNotifications[address] = disconnect
            }
        }

        // Devices reported right after start() were already connected: no activity for them.
        guard Date().timeIntervalSince(startedAt) >= BluetoothService.startupGrace else { return }
        guard !alreadyKnown else { return }

        let initial = BluetoothService.makeEvent(device: device, connected: true)
        events.send(initial)

        if initial.battery == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self = self, device.isConnected() else { return }
                let update = BluetoothService.makeEvent(device: device, connected: true)
                if update.battery != nil {
                    self.events.send(update)
                }
            }
        }
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        note.unregister()
        let address = BluetoothService.address(of: device)
        disconnectNotifications.removeValue(forKey: address)
        events.send(BluetoothService.makeEvent(device: device, connected: false))
    }

    // MARK: Helpers

    private static func name(of device: IOBluetoothDevice) -> String {
        let name: String? = device.name
        return name ?? ""
    }

    private static func address(of device: IOBluetoothDevice) -> String {
        let address: String? = device.addressString
        if let address = address, !address.isEmpty { return address }
        return name(of: device)
    }

    private static func makeEvent(device: IOBluetoothDevice, connected: Bool) -> BluetoothEvent {
        let deviceName = name(of: device)
        let kind = BluetoothDeviceKind.classify(
            name: deviceName,
            majorClass: UInt32(device.deviceClassMajor),
            minorClass: UInt32(device.deviceClassMinor)
        )
        return BluetoothEvent(
            address: address(of: device),
            name: deviceName.isEmpty ? "Bluetooth device" : deviceName,
            kind: kind,
            battery: connected ? battery(of: device) : nil,
            connected: connected
        )
    }

    /// Best effort: private, undocumented properties that some macOS versions expose for Apple audio devices.
    private static func battery(of device: IOBluetoothDevice) -> Int? {
        for key in batteryKeys {
            guard device.responds(to: NSSelectorFromString(key)) else { continue }
            if let number = device.value(forKey: key) as? NSNumber {
                let value = number.intValue
                if (1...100).contains(value) { return value }
            }
        }
        return nil
    }
}
