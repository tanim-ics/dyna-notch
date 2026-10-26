import AudioToolbox
import Combine
import CoreAudio
import Foundation
import os
import DynaNotchCore

/// 'vmvc' — kAudioHardwareServiceDeviceProperty_VirtualMainVolume (AudioToolbox/AudioHardwareService).
private let kVirtualMainVolume = AudioObjectPropertySelector(0x766D7663)

/// System output volume via CoreAudio. Listeners fire on the main queue.
final class VolumeService {
    static let shared = VolumeService()

    let changes = PassthroughSubject<LevelReading, Never>()

    private typealias ListenerBlock = @convention(block) (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "volume")
    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private let unknownObject = AudioObjectID(kAudioObjectUnknown)
    private let outputScope = AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput)
    private let globalScope = AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal)
    private let mainElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
    private let volumeScalar = AudioObjectPropertySelector(kAudioDevicePropertyVolumeScalar)
    private let muteSelector = AudioObjectPropertySelector(kAudioDevicePropertyMute)

    private var started = false
    private var startedAt = Date.distantPast
    private var lastReading: LevelReading?

    private var systemListener: ListenerBlock?
    private var deviceListener: ListenerBlock?
    private var listenedDevice = AudioObjectID(kAudioObjectUnknown)
    private var listenedAddresses: [AudioObjectPropertyAddress] = []

    private init() {}

    // MARK: Public API

    func start() {
        guard !started else { return }
        started = true
        startedAt = Date()

        let block: ListenerBlock = { [weak self] _, _ in
            self?.defaultDeviceChanged()
        }
        systemListener = block
        var address = defaultDeviceAddress()
        let status = AudioObjectAddPropertyListenerBlock(systemObject, &address, DispatchQueue.main, block)
        if status != 0 {
            logger.error("could not observe default output device (\(status))")
        }
        attach(to: defaultOutputDevice())
        lastReading = read()
    }

    func read() -> LevelReading? {
        guard let device = defaultOutputDevice(), let level = readVolume(device) else { return nil }
        let muted = readMute(device) ?? false
        return LevelReading(level: min(max(Double(level), 0), 1), muted: muted)
    }

    @discardableResult
    func setLevel(_ v: Double) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        let value = v.isFinite ? min(max(v, 0), 1) : 0
        if value > 0, readMute(device) == true {
            _ = writeMute(device, false)
        }
        return writeVolume(device, Float32(value))
    }

    @discardableResult
    func setMuted(_ m: Bool) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        return writeMute(device, m)
    }

    // MARK: Listeners (main queue)

    private func defaultDeviceChanged() {
        attach(to: defaultOutputDevice())
        valueChanged()
    }

    private func valueChanged() {
        guard let reading = read() else { return }
        if let last = lastReading, last == reading { return }
        lastReading = reading
        guard Date().timeIntervalSince(startedAt) >= 1.0 else { return }
        changes.send(reading)
    }

    private func attach(to device: AudioObjectID?) {
        if let device = device, device == listenedDevice, deviceListener != nil { return }
        detach()
        guard let device = device else { return }

        let block: ListenerBlock = { [weak self] _, _ in
            self?.valueChanged()
        }
        let candidates = [
            address(kVirtualMainVolume, scope: outputScope, element: mainElement),
            address(muteSelector, scope: outputScope, element: mainElement),
            address(muteSelector, scope: outputScope, element: 1),
            address(volumeScalar, scope: outputScope, element: mainElement),
            address(volumeScalar, scope: outputScope, element: 1),
            address(volumeScalar, scope: outputScope, element: 2),
        ]
        var registered: [AudioObjectPropertyAddress] = []
        for candidate in candidates {
            var a = candidate
            guard AudioObjectHasProperty(device, &a) else { continue }
            if AudioObjectAddPropertyListenerBlock(device, &a, DispatchQueue.main, block) == 0 {
                registered.append(candidate)
            }
        }
        deviceListener = block
        listenedDevice = device
        listenedAddresses = registered
    }

    private func detach() {
        if let block = deviceListener, listenedDevice != unknownObject {
            for candidate in listenedAddresses {
                var a = candidate
                _ = AudioObjectRemovePropertyListenerBlock(listenedDevice, &a, DispatchQueue.main, block)
            }
        }
        deviceListener = nil
        listenedDevice = unknownObject
        listenedAddresses = []
    }

    // MARK: CoreAudio helpers

    private func address(_ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope,
                         element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func defaultDeviceAddress() -> AudioObjectPropertyAddress {
        address(AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice), scope: globalScope, element: mainElement)
    }

    private func defaultOutputDevice() -> AudioObjectID? {
        var a = defaultDeviceAddress()
        var device = unknownObject
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(systemObject, &a, 0, nil, &size, &device)
        guard status == 0, device != unknownObject else { return nil }
        return device
    }

    private func has(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement) -> Bool {
        var a = address(selector, scope: outputScope, element: element)
        return AudioObjectHasProperty(device, &a)
    }

    private func isSettable(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement) -> Bool {
        var a = address(selector, scope: outputScope, element: element)
        guard AudioObjectHasProperty(device, &a) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &a, &settable) == 0 else { return false }
        return settable.boolValue
    }

    private func getFloat(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement) -> Float32? {
        var a = address(selector, scope: outputScope, element: element)
        guard AudioObjectHasProperty(device, &a) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value) == 0 else { return nil }
        return value
    }

    private func setFloat(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement, _ newValue: Float32) -> Bool {
        guard isSettable(device, selector, element) else { return false }
        var a = address(selector, scope: outputScope, element: element)
        var value = newValue
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(device, &a, 0, nil, size, &value) == 0
    }

    private func getUInt32(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement) -> UInt32? {
        var a = address(selector, scope: outputScope, element: element)
        guard AudioObjectHasProperty(device, &a) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value) == 0 else { return nil }
        return value
    }

    private func setUInt32(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement, _ newValue: UInt32) -> Bool {
        guard isSettable(device, selector, element) else { return false }
        var a = address(selector, scope: outputScope, element: element)
        var value = newValue
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(device, &a, 0, nil, size, &value) == 0
    }

    private func readVolume(_ device: AudioObjectID) -> Float32? {
        if let v = getFloat(device, kVirtualMainVolume, mainElement) { return v }
        if let v = getFloat(device, volumeScalar, mainElement) { return v }
        let channels = [getFloat(device, volumeScalar, 1), getFloat(device, volumeScalar, 2)].compactMap { $0 }
        guard !channels.isEmpty else { return nil }
        return channels.reduce(0, +) / Float32(channels.count)
    }

    private func writeVolume(_ device: AudioObjectID, _ value: Float32) -> Bool {
        if has(device, kVirtualMainVolume, mainElement), setFloat(device, kVirtualMainVolume, mainElement, value) {
            return true
        }
        if setFloat(device, volumeScalar, mainElement, value) { return true }
        let left = setFloat(device, volumeScalar, 1, value)
        let right = setFloat(device, volumeScalar, 2, value)
        return left || right
    }

    private func readMute(_ device: AudioObjectID) -> Bool? {
        if let m = getUInt32(device, muteSelector, mainElement) { return m != 0 }
        if let m = getUInt32(device, muteSelector, 1) { return m != 0 }
        return nil
    }

    private func writeMute(_ device: AudioObjectID, _ muted: Bool) -> Bool {
        let value: UInt32 = muted ? 1 : 0
        if setUInt32(device, muteSelector, mainElement, value) { return true }
        let left = setUInt32(device, muteSelector, 1, value)
        let right = setUInt32(device, muteSelector, 2, value)
        return left || right
    }
}
