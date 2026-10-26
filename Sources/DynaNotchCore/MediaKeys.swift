import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// NX_KEYTYPE_* codes.
public enum MediaKey: Int, Equatable {
    case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7,
         play = 16, next = 17, previous = 18, fast = 19, rewind = 20, illuminationUp = 21, illuminationDown = 22
}

public struct MediaKeyEvent: Equatable {
    public let rawKeyCode: Int
    public let key: MediaKey?
    public let isDown: Bool
    public let isRepeat: Bool

    /// NSEvent.data1 of a systemDefined (subtype 8) event: code = (d >> 16) & 0xFFFF, flags = d & 0xFFFF,
    /// down = ((flags & 0xFF00) >> 8) == 0x0A, repeat = flags & 0x1 == 1
    public init(data1: Int) {
        let d = Int64(data1)
        let code = Int((d >> 16) & 0xFFFF)
        let flags = Int(d & 0xFFFF)
        rawKeyCode = code
        key = MediaKey(rawValue: code)
        isDown = ((flags & 0xFF00) >> 8) == 0x0A
        isRepeat = (flags & 0x1) == 1
    }
}

public enum LevelStepper {
    public static let step: Double = 1.0 / 16.0
    public static let fineStep: Double = 1.0 / 64.0

    /// Moves to the next multiple of the step in the given direction, clamped 0...1.
    public static func step(_ level: Double, up: Bool, fine: Bool) -> Double {
        let size: Double = fine ? fineStep : LevelStepper.step
        let current = level.isFinite ? level : 0
        let result: Double
        if up {
            result = ((current / size + 1e-6).rounded(.down) + 1) * size
        } else {
            result = ((current / size - 1e-6).rounded(.up) - 1) * size
        }
        return min(1, max(0, result))
    }
}

public struct LevelReading: Equatable {
    public var level: Double
    public var muted: Bool
    public init(level: Double, muted: Bool) {
        self.level = level
        self.muted = muted
    }
}
