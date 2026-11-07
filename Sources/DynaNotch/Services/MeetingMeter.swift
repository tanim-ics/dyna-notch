import AVFoundation
import Combine
import Foundation
import os
import DynaNotchCore

/// Meeting Meter (CONTRACTS §6.16): the mic on for 15 s is a call — a live timer in the pill, a recap when it ends,
/// and (opt-in) your share of speaking time from the mic *level* (AVAudioEngine; nothing recorded or stored).
final class MeetingMeter {
    static let shared = MeetingMeter()
    static let callAfter: TimeInterval = 15

    struct Call: Equatable {
        var app: String
        var startedAt: Date
        var talkShare: Int?
    }

    /// Main queue: the call (renewed every 10 s while it lasts), nil when it ended.
    let calls = PassthroughSubject<Call?, Never>()

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "meeting")
    private var started = false
    private var cancellables = Set<AnyCancellable>()
    private var micOnSince: Date?
    private var micApp = ""
    private var pending: DispatchWorkItem?
    private var renew: AnyCancellable?
    private(set) var call: Call?
    private var meter = TalkMeter()
    private var engine: AVAudioEngine?

    private init() {}

    /// state.json `privacy.call`.
    var state: String {
        guard let call = call else { return "none" }
        return "\(call.app) since \(Int(call.startedAt.timeIntervalSince1970)) talk \(call.talkShare.map(String.init) ?? "-")"
    }

    func start() {
        guard !started else { return }
        started = true
        PrivacyMonitor.shared.changes
            .filter { $0.0 == .microphone }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, active, app in active ? self?.micOn(app: app) : self?.micOff() }
            .store(in: &cancellables)
        AppSettings.shared.$meetingTalkShare
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in
                if on { MeetingMeter.requestMicrophone() }
                if self?.call != nil { on ? self?.startListening() : self?.stopListening() }
            }
            .store(in: &cancellables)
    }

    /// Asks once, when the user turns Talk Share on (never at launch).
    static func requestMicrophone() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    static var microphoneAllowed: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }

    // MARK: Call lifecycle (main queue)

    private func micOn(app: String) {
        guard AppSettings.shared.meetingMeter, call == nil, micOnSince == nil else { return }
        micOnSince = Date()
        micApp = app
        let item = DispatchWorkItem { [weak self] in self?.beginCall() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + MeetingMeter.callAfter, execute: item)
    }

    private func beginCall() {
        guard let since = micOnSince, PrivacyMonitor.shared.inUse.contains(.microphone) else { return }
        if micApp.isEmpty { micApp = PrivacyMonitor.microphoneApps().first ?? "Call" }
        call = Call(app: micApp, startedAt: since, talkShare: nil)
        meter = TalkMeter()
        if AppSettings.shared.meetingTalkShare { startListening() }
        calls.send(call)
        renew = Timer.publish(every: 10, tolerance: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, var call = self.call else { return }
                call.talkShare = self.meter.share
                self.call = call
                self.calls.send(call)
            }
    }

    private func micOff() {
        pending?.cancel()
        pending = nil
        micOnSince = nil
        renew = nil
        stopListening()
        guard let ended = call else { return }
        call = nil
        calls.send(nil)
        let seconds = Date().timeIntervalSince(ended.startedAt)
        ScreenRecorder.notify(title: ended.app, body: CallFormat.recap(seconds: seconds, talkShare: meter.share),
                              symbol: "phone.down.fill")
    }

    // MARK: Talk share (opt-in)

    private func startListening() {
        guard engine == nil, MeetingMeter.microphoneAllowed else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            var sum: Float = 0
            for i in 0..<n { sum += samples[i] * samples[i] }
            let rms = sqrt(sum / Float(n))
            let db = 20 * log10(max(Double(rms), 1e-9))
            let seconds = Double(n) / format.sampleRate
            DispatchQueue.main.async { self?.meter.add(level: db, seconds: seconds) }
        }
        do {
            try engine.start()
            self.engine = engine
        } catch {
            input.removeTap(onBus: 0)
            logger.error("talk meter could not start: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func stopListening() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }
}
