import AVFoundation
import Combine
import Foundation
import os
import DynaNotchCore

/// Focus Soundscapes (CONTRACTS §6.17): rain, brown / pink noise and a fireplace, generated sample by sample (no
/// files). With Pomodoro on, it starts with a focus phase and fades out on breaks.
final class SoundscapeService: ObservableObject {
    static let shared = SoundscapeService()

    @Published private(set) var playing: Soundscape = .none

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "soundscape")
    private var engine: AVAudioEngine?
    private var cancellables = Set<AnyCancellable>()
    private var started = false
    private let generator = NoiseGenerator()

    private init() {}

    var isPlaying: Bool { playing != .none }

    func start() {
        guard !started else { return }
        started = true
        let settings = AppSettings.shared
        settings.$soundscapeVolume
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.engine?.mainMixerNode.outputVolume = Float(v) }
            .store(in: &cancellables)
        TimerService.shared.$engine
            .map { FocusGuard.isFocusing($0.state) }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] focusing in
                guard settings.soundscapeWithPomodoro, let sound = Soundscape(rawValue: settings.soundscape),
                      sound != .none else { return }
                focusing ? self?.play(sound) : self?.stop()
            }
            .store(in: &cancellables)
    }

    func play(_ sound: Soundscape) {
        guard sound != .none else { stop(); return }
        AppSettings.shared.soundscape = sound.rawValue
        generator.kind = sound
        if engine == nil {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else { return }
            let engine = AVAudioEngine()
            let gen = generator
            let node = AVAudioSourceNode(format: format) { _, _, frameCount, buffers -> OSStatus in
                gen.render(frameCount: Int(frameCount), into: UnsafeMutableAudioBufferListPointer(buffers))
                return noErr
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = Float(AppSettings.shared.soundscapeVolume)
            do {
                try engine.start()
                self.engine = engine
            } catch {
                logger.error("soundscape could not start: \(error.localizedDescription, privacy: .private)")
                return
            }
        }
        playing = sound
    }

    /// Fades out over a second, then releases the audio engine.
    func stop() {
        guard let engine = engine else { playing = .none; return }
        let start = engine.mainMixerNode.outputVolume
        for step in 1...10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 * Double(step)) { [weak self] in
                guard let self = self, self.engine === engine else { return }
                engine.mainMixerNode.outputVolume = start * Float(10 - step) / 10
                if step == 10 {
                    engine.stop()
                    self.engine = nil
                }
            }
        }
        playing = .none
    }
}

/// Fills audio buffers on the render thread: no allocation, no locks (the kind is a plain value swap).
private final class NoiseGenerator {
    var kind: Soundscape = .rain
    private var brown: Float = 0
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0     // pink filter state
    private var lowpass: Float = 0
    private var crackle: Float = 0
    private var seed: UInt32 = 0x1234_5678

    private func white() -> Float {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Float(seed) / Float(UInt32.max) * 2 - 1
    }

    func render(frameCount: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for i in 0..<frameCount { data[i] = sample() }
        }
    }

    private func sample() -> Float {
        let w = white()
        switch kind {
        case .none:
            return 0
        case .brown:
            brown = (brown + 0.02 * w) / 1.02
            return brown * 3.5
        case .pink:
            b0 = 0.99765 * b0 + w * 0.0990460
            b1 = 0.96300 * b1 + w * 0.2965164
            b2 = 0.57000 * b2 + w * 1.0526913
            return (b0 + b1 + b2 + w * 0.1848) * 0.11
        case .rain:
            // Pink-ish hiss, slightly brighter than pink, with sparse soft drops.
            b0 = 0.99765 * b0 + w * 0.0990460
            b1 = 0.96300 * b1 + w * 0.2965164
            let hiss = (b0 + b1 + w * 0.5) * 0.12
            if white() > 0.9993 { crackle = 0.35 }
            crackle *= 0.995
            return hiss + crackle * white()
        case .fire:
            // Low rumble with random crackles.
            brown = (brown + 0.02 * w) / 1.02
            lowpass += 0.05 * (brown - lowpass)
            if white() > 0.9996 { crackle = 0.9 }
            crackle *= 0.97
            return lowpass * 2.5 + crackle * white()
        }
    }
}
