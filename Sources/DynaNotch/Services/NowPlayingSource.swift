import Foundation

/// Which engine currently feeds `NowPlayingService`.
enum NowPlayingSource: String {
    case none
    case mediaRemote
    case appleScript
}
