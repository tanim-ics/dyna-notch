import Foundation
import os

/// Locks the screen: private `SACLockScreenImmediate` (login.framework) when present, else display sleep.
enum ScreenLock {
    private typealias LockFunction = @convention(c) () -> Int32

    static func lock() {
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        if let handle = dlopen(path, RTLD_LAZY), let symbol = dlsym(handle, "SACLockScreenImmediate") {
            let function = unsafeBitCast(symbol, to: LockFunction.self)
            _ = function()
            return
        }
        Logger(subsystem: "com.tanim.dynanotch", category: "lock").info("SACLockScreenImmediate unavailable; sleeping display")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        try? task.run()
    }
}
