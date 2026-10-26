import AppKit

/// One-shot actions from the panel's "⋯" menu.
enum QuickActions {
    /// Interactive area screenshot straight to the clipboard (it then shows up in Clipboard history).
    static func captureScreenshot() {
        // Give the panel a moment to collapse so it is not in the shot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-i", "-c"]
            try? task.run()
        }
    }

    /// System colour picker loupe; the picked colour is copied as "#RRGGBB".
    static func pickColor() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSColorSampler().show { color in
                guard let rgb = color?.usingColorSpace(.sRGB) else { return }
                let hex = String(format: "#%02X%02X%02X",
                                 Int((rgb.redComponent * 255).rounded()),
                                 Int((rgb.greenComponent * 255).rounded()),
                                 Int((rgb.blueComponent * 255).rounded()))
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(hex, forType: .string)
            }
        }
    }
}
