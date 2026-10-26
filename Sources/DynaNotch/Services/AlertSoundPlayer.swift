import AppKit
import DynaNotchCore

/// Per-category alert sounds (Settings → Popups → Sounds): `AlertSounds` mapping in settings.alertSounds.
enum AlertSoundPlayer {
    /// Plays the category's sound unless it is "None".
    static func play(_ category: AlertCategory) {
        preview(AlertSounds.sound(for: category, in: AppSettings.shared.alertSounds))
    }

    /// Plays a system sound by name (▶ buttons in Settings).
    static func preview(_ name: String) {
        guard name != AlertSounds.none, let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.stop()
        sound.play()
    }
}
