import AppKit
import Foundation
import os

/// A private SkyLight space above the lock screen (owner decision, DECISIONS §14). Windows moved into it stay visible
/// while the Mac is locked. Everything is resolved with `dlopen`/`dlsym`; when a symbol is missing or a call fails,
/// `isAvailable` is false and nothing is drawn on the lock screen.
final class SkyLightSpace {
    static let shared = SkyLightSpace()

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsAndRemoveFromSpaces = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    /// Absolute level of the space: `kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`, the level the system's
    /// own lock-screen notifications use (100 stays under the lock screen).
    private static let spaceLevel: Int32 = 400

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "skylight")
    private var loaded = false
    private var connection: Int32 = 0
    private var space: Int32 = 0
    private var addWindows: AddWindowsAndRemoveFromSpaces?

    /// Whether `delegate(_:)` made the call (state.json `lockScreen.delegated`).
    private(set) var lastDelegateSucceeded = false
    /// Raw result of the last `SLSSpaceAddWindowsAndRemoveFromSpaces` call (state.json `lockScreen.result`).
    private(set) var lastResult: Int32 = 0

    private init() {}

    /// The space's ID (state.json `lockScreen.space`).
    var spaceID: Int32 { space }

    /// state.json: "not loaded" until the first lock with the strip on, then "available" / "unavailable".
    var status: String {
        guard loaded else { return "not loaded" }
        return addWindows != nil && space != 0 ? "available" : "unavailable"
    }

    /// Loads SkyLight and creates the space on first use (main queue).
    var isAvailable: Bool {
        load()
        return addWindows != nil && space != 0
    }

    /// Moves the window into the lock-screen space. False only when SkyLight is unavailable.
    @discardableResult
    func delegate(_ window: NSWindow) -> Bool {
        guard isAvailable, let addWindows = addWindows else {
            lastDelegateSucceeded = false
            return false
        }
        let result = addWindows(connection, space, [window.windowNumber] as CFArray, 7)
        lastResult = result
        // Not a reliable status on macOS 27 (3 even when the window moves): the caller checks the window instead.
        lastDelegateSucceeded = true
        logger.debug("SLSSpaceAddWindowsAndRemoveFromSpaces returned \(result, privacy: .public)")
        return true
    }

    /// Whether the window server has the window on screen (diagnostics). On macOS 27 the SkyLight calls return 3 even
    /// when they work, and `SLSCopySpacesForWindows` does not list custom spaces, so this is the usable check.
    static func isOnScreen(_ window: NSWindow) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains { ($0[kCGWindowNumber as String] as? Int) == window.windowNumber }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
        guard let handle = dlopen(path, RTLD_NOW),
              let mainSym = dlsym(handle, "SLSMainConnectionID"),
              let createSym = dlsym(handle, "SLSSpaceCreate"),
              let levelSym = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
              let showSym = dlsym(handle, "SLSShowSpaces"),
              let addSym = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces") else {
            logger.info("SkyLight lock-screen space unavailable; lock-screen widgets are off")
            return
        }
        let mainConnection = unsafeBitCast(mainSym, to: MainConnectionID.self)
        let create = unsafeBitCast(createSym, to: SpaceCreate.self)
        let setLevel = unsafeBitCast(levelSym, to: SpaceSetAbsoluteLevel.self)
        let show = unsafeBitCast(showSym, to: ShowSpaces.self)

        connection = mainConnection()
        let newSpace = create(connection, 1, 0)
        guard connection != 0, newSpace != 0 else {
            logger.error("SLSSpaceCreate failed")
            return
        }
        _ = setLevel(connection, newSpace, SkyLightSpace.spaceLevel)
        _ = show(connection, [newSpace] as CFArray)
        space = newSpace
        addWindows = unsafeBitCast(addSym, to: AddWindowsAndRemoveFromSpaces.self)
    }
}
