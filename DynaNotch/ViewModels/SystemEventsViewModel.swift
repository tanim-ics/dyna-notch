import Foundation
import CoreAudio
import IOKit.ps

class SystemEventsViewModel: ObservableObject {
    weak var notchVM: NotchViewModel?
    private var lastVolume: Float = -1
    private var currentDeviceID: AudioDeviceID = 0
    private var isACConnected: Bool? = nil
    private var powerRunLoopSource: CFRunLoopSource?

    static let shared = SystemEventsViewModel()

    func connect(to vm: NotchViewModel) {
        self.notchVM = vm
        setupAudioListener()
        setupPowerListener()
        // Record initial volume without popping HUD
        lastVolume = getSystemVolume()
    }

    // MARK: – CoreAudio Real-Time Event Listener
    private func setupAudioListener() {
        // 1. Listen for default output device changes (e.g. headphones plugged in)
        var defaultDeviceAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddr,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.updateOutputDeviceListener()
        }

        updateOutputDeviceListener()
    }

    private func updateOutputDeviceListener() {
        let newDeviceID = getDefaultOutputDeviceID()
        guard newDeviceID != kAudioObjectUnknown, newDeviceID != currentDeviceID else { return }

        currentDeviceID = newDeviceID

        // Listen for volume changes on master channel (0)
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 0
        )

        AudioObjectAddPropertyListenerBlock(
            newDeviceID,
            &volAddr,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.handleVolumeChange()
        }

        // Also channel 1 (left/stereo master)
        var volAddr1 = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 1
        )

        AudioObjectAddPropertyListenerBlock(
            newDeviceID,
            &volAddr1,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.handleVolumeChange()
        }
    }

    private func handleVolumeChange() {
        guard let vm = notchVM, vm.showVolumeHUD else { return }
        let vol = getSystemVolume()
        guard vol >= 0 else { return }
        if lastVolume < 0 {
            lastVolume = vol
            return
        }
        if abs(vol - lastVolume) > 0.005 {
            lastVolume = vol
            DispatchQueue.main.async { [weak self] in
                self?.notchVM?.showHUD(.volume(vol))
            }
        }
    }

    private func getDefaultOutputDeviceID() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size, &deviceID
        )
        return (status == noErr) ? deviceID : kAudioObjectUnknown
    }

    private func getSystemVolume() -> Float {
        let deviceID = (currentDeviceID != 0 && currentDeviceID != kAudioObjectUnknown)
            ? currentDeviceID
            : getDefaultOutputDeviceID()

        guard deviceID != kAudioObjectUnknown else { return -1 }

        for channel: UInt32 in [0, 1] {
            var vol = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: channel
            )
            if AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol) == noErr {
                return vol
            }
        }
        return -1
    }

    // MARK: – Power Source / Battery Listener
    private func setupPowerListener() {
        let source = IOPSNotificationCreateRunLoopSource({ context in
            SystemEventsViewModel.shared.handlePowerSourceChange()
        }, nil)?.takeRetainedValue()

        if let source {
            powerRunLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        // Initialize state
        _ = readBatteryInfo()
    }

    func handlePowerSourceChange() {
        guard let info = readBatteryInfo() else { return }
        if let wasAC = isACConnected, wasAC != info.isAC {
            // Power connection state changed (plugged in or unplugged)
            isACConnected = info.isAC
            DispatchQueue.main.async { [weak self] in
                self?.notchVM?.showHUD(.battery(info.percent, isCharging: info.isCharging))
            }
        } else {
            isACConnected = info.isAC
        }
    }

    private func readBatteryInfo() -> (percent: Float, isCharging: Bool, isAC: Bool)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for item in list {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, item)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let current = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey as String] as? Int ?? 100
            let isCharging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
            let state = desc[kIOPSPowerSourceStateKey as String] as? String ?? ""
            let isAC = (state == (kIOPSACPowerValue as String))
            let percent = max > 0 ? Float(current) / Float(max) : 1.0
            return (percent, isCharging, isAC)
        }
        return nil
    }
}
