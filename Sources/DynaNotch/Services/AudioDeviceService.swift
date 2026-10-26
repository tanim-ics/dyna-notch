import Combine
import CoreAudio
import Foundation
import os

struct AudioDevice: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let isOutput: Bool
}

/// Output-device switching and microphone mute via CoreAudio. Listeners fire on the main queue.
final class AudioDeviceService: ObservableObject {
    static let shared = AudioDeviceService()

    @Published private(set) var outputs: [AudioDevice] = []
    @Published private(set) var currentOutputID: UInt32?
    @Published private(set) var isMicMuted = false

    private typealias ListenerBlock = @convention(block) (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "audiodevice")
    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private let unknownObject = AudioObjectID(kAudioObjectUnknown)
    private let globalScope = AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal)
    private let inputScope = AudioObjectPropertyScope(kAudioDevicePropertyScopeInput)
    private let outputScope = AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput)
    private let mainElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
    private let muteSelector = AudioObjectPropertySelector(kAudioDevicePropertyMute)
    private let volumeSelector = AudioObjectPropertySelector(kAudioDevicePropertyVolumeScalar)

    private var started = false
    private var systemListener: ListenerBlock?
    private var systemAddresses: [AudioObjectPropertyAddress] = []
    private var inputListener: ListenerBlock?
    private var inputDevice = AudioObjectID(kAudioObjectUnknown)
    private var inputAddresses: [AudioObjectPropertyAddress] = []
    /// Volume to restore when un-muting a device without a settable mute control (keyed by device).
    private var savedInputVolume: [AudioObjectID: Float32] = [:]

    private init() {}

    // MARK: Public API

    func start() {
        guard !started else { return }
        started = true

        let block: ListenerBlock = { [weak self] _, addresses in
            self?.systemPropertyChanged(addresses.pointee.mSelector)
        }
        systemListener = block
        let selectors = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice,
        ]
        for selector in selectors {
            var a = address(AudioObjectPropertySelector(selector), scope: globalScope)
            let status = AudioObjectAddPropertyListenerBlock(systemObject, &a, DispatchQueue.main, block)
            if status == 0 {
                systemAddresses.append(a)
            } else {
                logger.error("could not observe audio hardware property \(selector) (\(status))")
            }
        }

        reloadOutputs()
        attachInput(defaultDevice(input: true))
    }

    func select(_ device: AudioDevice) {
        var id = AudioObjectID(device.id)
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        var a = address(AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice), scope: globalScope)
        let status = AudioObjectSetPropertyData(systemObject, &a, 0, nil, size, &id)
        if status != 0 {
            logger.error("could not set default output (\(status))")
        }
        var s = address(AudioObjectPropertySelector(kAudioHardwarePropertyDefaultSystemOutputDevice), scope: globalScope)
        _ = AudioObjectSetPropertyData(systemObject, &s, 0, nil, size, &id)
        // The listener refreshes too, but update immediately for snappy UI.
        if status == 0 { currentOutputID = device.id }
    }

    func toggleMicMute() {
        guard let device = defaultDevice(input: true) else { return }
        let target = !(readMicMuted(device) ?? isMicMuted)
        if setInputMute(device, target) {
            // done
        } else if target {
            if let volume = getFloat(device, volumeSelector, scope: inputScope), volume > 0 {
                savedInputVolume[device] = volume
            }
            _ = setFloat(device, volumeSelector, scope: inputScope, 0)
        } else {
            let restore = savedInputVolume.removeValue(forKey: device) ?? 0.75
            _ = setFloat(device, volumeSelector, scope: inputScope, restore)
        }
        refreshMicMuted()
    }

    // MARK: Listeners (main queue)

    private func systemPropertyChanged(_ selector: AudioObjectPropertySelector) {
        switch selector {
        case AudioObjectPropertySelector(kAudioHardwarePropertyDefaultInputDevice):
            attachInput(defaultDevice(input: true))
        case AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice):
            let id = defaultDevice(input: false)
            if currentOutputID != id { currentOutputID = id }
        default:
            reloadOutputs()
            attachInput(defaultDevice(input: true))
        }
    }

    private func reloadOutputs() {
        let list = allDevices()
            .filter { hasStreams($0, scope: outputScope) }
            .map { AudioDevice(id: $0, name: name(of: $0) ?? "Audio Device \($0)", isOutput: true) }
        if outputs != list { outputs = list }
        let id = defaultDevice(input: false)
        if currentOutputID != id { currentOutputID = id }
    }

    private func attachInput(_ device: AudioObjectID?) {
        if let device = device, device == inputDevice, inputListener != nil {
            refreshMicMuted()
            return
        }
        detachInput()
        guard let device = device else {
            if isMicMuted { isMicMuted = false }
            return
        }
        let block: ListenerBlock = { [weak self] _, _ in
            self?.refreshMicMuted()
        }
        let candidates = [
            address(AudioObjectPropertySelector(kAudioDevicePropertyMute), scope: inputScope),
            address(AudioObjectPropertySelector(kAudioDevicePropertyVolumeScalar), scope: inputScope),
        ]
        var registered: [AudioObjectPropertyAddress] = []
        for candidate in candidates {
            var a = candidate
            guard AudioObjectHasProperty(device, &a) else { continue }
            if AudioObjectAddPropertyListenerBlock(device, &a, DispatchQueue.main, block) == 0 {
                registered.append(candidate)
            }
        }
        inputListener = block
        inputDevice = device
        inputAddresses = registered
        refreshMicMuted()
    }

    private func detachInput() {
        if let block = inputListener, inputDevice != unknownObject {
            for candidate in inputAddresses {
                var a = candidate
                _ = AudioObjectRemovePropertyListenerBlock(inputDevice, &a, DispatchQueue.main, block)
            }
        }
        inputListener = nil
        inputDevice = unknownObject
        inputAddresses = []
    }

    private func refreshMicMuted() {
        let muted = defaultDevice(input: true).flatMap { readMicMuted($0) } ?? false
        if isMicMuted != muted { isMicMuted = muted }
    }

    /// Muted if the mute control is on, or (fallback devices) the input volume is at zero while we hold a saved volume.
    private func readMicMuted(_ device: AudioObjectID) -> Bool? {
        if let mute = getUInt32(device, muteSelector, scope: inputScope), mute != 0 { return true }
        if let volume = getFloat(device, volumeSelector, scope: inputScope),
           volume <= 0.0001, savedInputVolume[device] != nil || !isSettable(device, muteSelector, scope: inputScope) {
            return true
        }
        if getUInt32(device, muteSelector, scope: inputScope) != nil { return false }
        if getFloat(device, volumeSelector, scope: inputScope) != nil { return false }
        return nil
    }

    private func setInputMute(_ device: AudioObjectID, _ muted: Bool) -> Bool {
        guard isSettable(device, muteSelector, scope: inputScope) else { return false }
        var a = address(AudioObjectPropertySelector(kAudioDevicePropertyMute), scope: inputScope)
        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        if status != 0 { return false }
        // If we muted by volume earlier, restore it now that the real control works.
        if !muted, let restore = savedInputVolume.removeValue(forKey: device),
           let volume = getFloat(device, volumeSelector, scope: inputScope), volume <= 0.0001 {
            _ = setFloat(device, volumeSelector, scope: inputScope, restore)
        }
        return true
    }

    // MARK: CoreAudio helpers

    private func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: mainElement)
    }

    private func defaultDevice(input: Bool) -> AudioObjectID? {
        let selector = input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        var a = address(AudioObjectPropertySelector(selector), scope: globalScope)
        var device = unknownObject
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(systemObject, &a, 0, nil, &size, &device)
        guard status == 0, device != unknownObject else { return nil }
        return device
    }

    private func allDevices() -> [AudioObjectID] {
        var a = address(AudioObjectPropertySelector(kAudioHardwarePropertyDevices), scope: globalScope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &a, 0, nil, &size) == 0, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        let status = ids.withUnsafeMutableBufferPointer { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return -1 }
            return AudioObjectGetPropertyData(systemObject, &a, 0, nil, &size, base)
        }
        guard status == 0 else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private func hasStreams(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var a = address(AudioObjectPropertySelector(kAudioDevicePropertyStreams), scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &a, 0, nil, &size) == 0 else { return false }
        return size > 0
    }

    private func name(of device: AudioObjectID) -> String? {
        var a = address(AudioObjectPropertySelector(kAudioObjectPropertyName), scope: globalScope)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(device, &a, 0, nil, &size, pointer)
        }
        guard status == 0, let value = name?.takeRetainedValue() else { return nil }
        let string = value as String
        return string.isEmpty ? nil : string
    }

    private func isSettable(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> Bool {
        var a = address(selector, scope: scope)
        guard AudioObjectHasProperty(device, &a) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &a, &settable) == 0 else { return false }
        return settable.boolValue
    }

    private func getUInt32(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> UInt32? {
        var a = address(selector, scope: scope)
        guard AudioObjectHasProperty(device, &a) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value) == 0 else { return nil }
        return value
    }

    private func getFloat(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> Float32? {
        var a = address(selector, scope: scope)
        guard AudioObjectHasProperty(device, &a) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value) == 0 else { return nil }
        return value
    }

    private func setFloat(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, _ newValue: Float32) -> Bool {
        guard isSettable(device, selector, scope: scope) else { return false }
        var a = address(selector, scope: scope)
        var value = newValue
        return AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == 0
    }
}
