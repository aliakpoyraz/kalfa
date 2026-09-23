import Foundation

/// Runs blocking work off the main thread with a hard deadline.
///
/// Window server IPC — `CGCompleteDisplayConfiguration` above all — can block for
/// seconds or never return at all when a display is mid-renegotiation, which is
/// precisely when Kalfa is doing its work. Every such call goes through here so a
/// wedged window server cannot freeze the menu bar.
enum Watchdog {

    static func run<T: Sendable>(
        seconds: Double,
        fallback: T,
        _ work: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            let state = ResumeOnce()

            DispatchQueue.global(qos: .userInitiated).async {
                let result = work()
                if state.claim() { continuation.resume(returning: result) }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                if state.claim() {
                    Log.display.warning("watchdog: timed out after \(seconds, privacy: .public)s")
                    continuation.resume(returning: fallback)
                }
            }
        }
    }

    /// Guarantees exactly one of the two racers resumes the continuation.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var used = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if used { return false }
            used = true
            return true
        }
    }
}
