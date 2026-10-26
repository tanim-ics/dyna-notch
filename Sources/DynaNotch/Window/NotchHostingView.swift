import AppKit
import SwiftUI

/// Hosting view that accepts the first click, so buttons work without activating the app first.
/// No initializers are declared on purpose: the subclass inherits `init(rootView:)` and `init?(coder:)`
/// from `NSHostingView`, which avoids any required-initializer / actor-isolation signature mismatch.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
