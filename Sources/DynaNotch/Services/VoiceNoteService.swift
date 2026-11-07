import AVFoundation
import Combine
import Foundation
import os
import Speech
import DynaNotchCore

/// Voice Notes (CONTRACTS §6.20): speak, and it becomes a note, a reminder or a timer. Recognition runs on this Mac
/// only (`requiresOnDeviceRecognition`); nothing is recorded or kept beyond the resulting text.
final class VoiceNoteService {
    static let shared = VoiceNoteService()
    static let maxSeconds: TimeInterval = 30
    static let silence: TimeInterval = 1.6

    /// Main queue: the live words (result nil) and, at the end, what happened.
    let updates = PassthroughSubject<(text: String, result: String?), Never>()

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "voice")
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var transcript = ""
    private var silenceWork: DispatchWorkItem?
    private var limitWork: DispatchWorkItem?
    private(set) var listening = false
    private(set) var last = "none"

    private init() {}

    var state: [String: Any] { ["listening": listening, "last": last] }

    /// Shortcut / knock: start listening, or finish if already listening.
    func toggle() {
        if listening { finish(); return }
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self.fail("Allow Speech Recognition in System Settings › Privacy & Security")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        granted ? self.begin() : self.fail("Allow the Microphone in System Settings › Privacy & Security")
                    }
                }
            }
        }
    }

    /// What a transcript does (also `dynanotch://voice?text=`).
    func handle(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            updates.send(("", "Didn't catch that"))
            return
        }
        let command = VoiceCommand.parse(trimmed)
        switch command {
        case .note(let note):
            let notes = NotesService.shared
            let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
            notes.text = notes.text.isEmpty ? "\(stamp) \(note)" : notes.text + "\n\(stamp) \(note)"
        case .reminder(let title):
            if RemindersService.shared.access == .granted {
                RemindersService.shared.add(title)
            } else {
                NotesService.shared.addTodo(title)   // no Reminders access: a to-do in the Notes tab
            }
        case .timer(let minutes):
            TimerService.shared.startCountdown(minutes: minutes, label: "Voice timer")
        }
        last = "\(command) ← \(trimmed)"
        updates.send((trimmed, command.resultLabel))
    }

    // MARK: Listening (main queue)

    private func begin() {
        let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer = recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            fail("On-device speech isn't available for this language")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { fail("No microphone"); return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            fail("The microphone couldn't start")
            return
        }
        self.engine = engine
        self.request = request
        transcript = ""
        listening = true
        updates.send(("", nil))
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self, self.listening else { return }
                if let result = result {
                    self.transcript = result.bestTranscription.formattedString
                    self.updates.send((self.transcript, nil))
                    self.armSilence()
                    if result.isFinal { self.finish() }
                } else if error != nil {
                    self.finish()
                }
            }
        }
        let limit = DispatchWorkItem { [weak self] in self?.finish() }
        limitWork = limit
        DispatchQueue.main.asyncAfter(deadline: .now() + VoiceNoteService.maxSeconds, execute: limit)
        armSilence()
    }

    private func armSilence() {
        silenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.finish() }
        silenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + VoiceNoteService.silence + (transcript.isEmpty ? 3 : 0),
                                      execute: work)
    }

    private func finish() {
        guard listening else { return }
        listening = false
        silenceWork?.cancel()
        limitWork?.cancel()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        request?.endAudio()
        task?.cancel()
        engine = nil
        request = nil
        task = nil
        handle(transcript)
    }

    private func fail(_ message: String) {
        logger.error("voice note: \(message, privacy: .private)")
        last = "failed: \(message)"
        updates.send(("", message))
    }
}
