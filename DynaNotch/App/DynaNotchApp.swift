import SwiftUI

@main
struct DynaNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty scene — all windows are managed by AppDelegate
        Settings { EmptyView() }
    }
}
