import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A Bluetooth device connect / disconnect event (see `BluetoothDeviceKind.classify` in Activities.swift).
public struct BluetoothEvent: Equatable {
    public var address: String
    public var name: String
    public var kind: BluetoothDeviceKind
    public var battery: Int?
    public var connected: Bool

    public init(address: String, name: String, kind: BluetoothDeviceKind, battery: Int?, connected: Bool) {
        self.address = address
        self.name = name
        self.kind = kind
        self.battery = battery
        self.connected = connected
    }
}
