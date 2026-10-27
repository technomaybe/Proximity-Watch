import Foundation

/// Locks the Mac the same way Control-Command-Q does.
enum ScreenLocker {
    /// Returns false if the private lock function couldn't be found, so the caller can fall back.
    @discardableResult
    static func lock() -> Bool {
        // SACLockScreenImmediate lives in Apple's private login framework. BLEUnlock and
        // similar apps use it because there's no public "lock now" API.
        typealias LockFunction = @convention(c) () -> Int32
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        guard let handle = dlopen(path, RTLD_LAZY), let symbol = dlsym(handle, "SACLockScreenImmediate") else {
            return false
        }
        _ = unsafeBitCast(symbol, to: LockFunction.self)()
        return true
    }

    /// Fallback: sleep the display. This locks only if "Require password after
    /// screen saver begins or display is turned off" is set to Immediately.
    static func sleepDisplay() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        try? task.run()
    }
}
