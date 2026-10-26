import Combine
import CoreAudio
import CoreMediaIO
import Foundation
import os
import DynaNotchCore

/// Reports when any app starts/stops using the camera or microphone (1.5 s poll, main queue).
final class PrivacyMonitor {
    static let shared = PrivacyMonitor()

    let changes = PassthroughSubject<(SensorKind, Bool), Never>()

    private var started = false
    private var timer: AnyCancellable?
    private var lastState: [SensorKind: Bool]?

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        timer = Timer.publish(every: 1.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.poll() }
        poll()
    }

    // MARK: Private (main queue)

    private func poll() {
        let state: [SensorKind: Bool] = [
            .camera: PrivacyMonitor.isCameraInUse(),
            .microphone: PrivacyMonitor.isMicrophoneInUse(),
        ]
        defer { lastState = state }
        guard let previous = lastState else { return }   // first poll only seeds
        for kind in SensorKind.allCases {
            let now = state[kind] ?? false
            if (previous[kind] ?? false) != now {
                changes.send((kind, now))
            }
        }
    }

    private static func isCameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == 0, size > 0 else { return false }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        let status = devices.withUnsafeMutableBufferPointer { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return -1 }
            return CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, base)
        }
        guard status == 0 else { return false }

        let usedCount = min(count, Int(used) / MemoryLayout<CMIOObjectID>.size)
        for device in devices.prefix(usedCount) {
            var running = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            guard CMIOObjectHasProperty(device, &running) else { continue }
            var value: UInt32 = 0
            var valueUsed: UInt32 = 0
            let result = CMIOObjectGetPropertyData(device, &running, 0, nil,
                                                   UInt32(MemoryLayout<UInt32>.size), &valueUsed, &value)
            if result == 0, value != 0 { return true }
        }
        return false
    }

    private static func isMicrophoneInUse() -> Bool {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultInputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &defaultAddress, 0, nil, &size, &device) == 0,
              device != AudioObjectID(kAudioObjectUnknown) else { return false }

        var runningAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyDeviceIsRunningSomewhere),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
        guard AudioObjectHasProperty(device, &runningAddress) else { return false }
        var running: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &runningAddress, 0, nil, &runningSize, &running) == 0 else { return false }
        return running != 0
    }
}
