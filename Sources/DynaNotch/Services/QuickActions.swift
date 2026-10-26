import AppKit
import os

/// One-shot actions from the panel's "⋯" menu.
enum QuickActions {
    private static let logger = Logger(subsystem: "com.tanim.dynanotch", category: "quickactions")

    /// Interactive area screenshot. Default: straight to the clipboard (it then shows up in Clipboard history).
    /// With `screenshotFolder`: saved there as "Screenshot <date>.png" and copied to the clipboard.
    /// With `screenshotToShelf`: saved (to that folder, else App Support/Screenshots) and added to the Shelf.
    static func captureScreenshot() {
        // Give the panel a moment to collapse so it is not in the shot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let settings = AppSettings.shared
            if let folder = customFolder() {
                captureToFile(in: folder, addToShelf: settings.screenshotToShelf)
            } else if settings.screenshotToShelf {
                captureToFile(in: screenshotsDirectory, addToShelf: true)
            } else {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                task.arguments = ["-i", "-c"]
                do { try task.run() } catch {
                    logger.error("screencapture failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Records the whole screen (`screencapture -v`) until stopped from the ⋯ menu.
    static func recordScreen() {
        ScreenRecorder.shared.start(area: false)
    }

    /// Records a dragged-out area (`screencapture -v -i -s`); Esc during the selection cancels.
    static func recordArea() {
        ScreenRecorder.shared.start(area: true)
    }

    /// Settings → Screenshots → Save to (expanded, nil when empty = default behaviour).
    static func customFolder() -> URL? {
        let raw = AppSettings.shared.screenshotFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// "Screenshot 2026-10-26 at 14.03.22" (no extension).
    static func timestampedName(_ prefix: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(formatter.string(from: Date()))"
    }

    static func pickColor() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSColorSampler().show { color in
                guard let color = color, let text = format(color, as: AppSettings.shared.colorFormat) else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                ColorHistory.shared.add(text)
            }
        }
    }

    /// Formats a colour as "hex" (default), "rgb" or "hsl".
    static func format(_ color: NSColor, as format: String) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let r = min(max(rgb.redComponent, 0), 1)
        let g = min(max(rgb.greenComponent, 0), 1)
        let b = min(max(rgb.blueComponent, 0), 1)
        let r255 = Int((r * 255).rounded()), g255 = Int((g * 255).rounded()), b255 = Int((b * 255).rounded())
        switch format {
        case "rgb":
            return "rgb(\(r255), \(g255), \(b255))"
        case "hsl":
            let maxC = max(r, g, b), minC = min(r, g, b)
            let lightness = (maxC + minC) / 2
            let delta = maxC - minC
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            if delta > 0 {
                saturation = delta / (1 - abs(2 * lightness - 1))
                if maxC == r {
                    hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
                } else if maxC == g {
                    hue = (b - r) / delta + 2
                } else {
                    hue = (r - g) / delta + 4
                }
                hue *= 60
                if hue < 0 { hue += 360 }
            }
            return "hsl(\(Int(hue.rounded()) % 360), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%)"
        default:
            return String(format: "#%02X%02X%02X", r255, g255, b255)
        }
    }

    // MARK: Private

    private static var screenshotsDirectory: URL {
        AppDataStore.directory.appendingPathComponent("Screenshots", isDirectory: true)
    }

    private static func captureToFile(in directory: URL, addToShelf: Bool) {
        let url = directory.appendingPathComponent(timestampedName("Screenshot") + ".png")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                task.arguments = ["-i", url.path]
                try task.run()
                task.waitUntilExit()
            } catch {
                logger.error("screencapture failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            // Esc during the interactive capture leaves no file.
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            DispatchQueue.main.async {
                if addToShelf { ShelfService.shared.add(urls: [url]) }
                if let image = NSImage(contentsOf: url) {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([image])
                }
                logger.info("screenshot saved to \(url.path, privacy: .public)")
            }
        }
    }
}
