import CoreGraphics
import Foundation

/// Reads and applies display modes.
///
/// Two things here are not obvious:
///
/// 1. `kCGDisplayShowDuplicateLowResolutionModes` is required to see HiDPI modes
///    at all. Without it `CGDisplayCopyAllDisplayModes` returns only the subset
///    System Settings shows, which hides the scaled Retina variants.
///
/// 2. A mode is applied inside a `CGDisplayConfiguration` transaction so several
///    displays can be reconfigured atomically. Restoring a profile one display at
///    a time makes the desktop relayout twice and can leave windows off-screen.
enum ModeService {

    /// Computed rather than stored: `CFDictionary` is not `Sendable`, and a shared
    /// static would be a data race under strict concurrency for no benefit.
    private static var listOptions: CFDictionary {
        [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
    }

    // MARK: Reading

    /// Every mode a display can be put into, from both lists, in menu order.
    ///
    /// SkyLight is read first and CoreGraphics second so that any mode present in
    /// both keeps the CoreGraphics description — it carries the authoritative
    /// pixel size and has already passed the desktop-usability check.
    static func modes(for displayID: CGDirectDisplayID) -> [ScreenMode] {
        var byID: [Int32: ScreenMode] = [:]

        for entry in SkyLightModes.entries(for: displayID) {
            let mode = ScreenMode(entry)
            guard isPlausible(mode) else { continue }
            byID[mode.id] = mode
        }

        for raw in rawModes(for: displayID) where raw.isUsableForDesktopGUI() {
            let mode = ScreenMode(raw)
            byID[mode.id] = mode
        }

        return byID.values.sorted(by: ScreenMode.menuOrder)
    }

    /// SkyLight's list includes entries no desktop should ever use — zero refresh
    /// rates, sizes below the smallest sane desktop, television timings.
    private static func isPlausible(_ mode: ScreenMode) -> Bool {
        mode.width >= 640
            && mode.height >= 480
            && mode.refreshRate > 0
            && !mode.isTelevision
    }

    static func current(for displayID: CGDirectDisplayID) -> ScreenMode? {
        CGDisplayCopyDisplayMode(displayID).map(ScreenMode.init)
    }

    /// The mode macOS reports as the panel's own native timing, if it advertises one.
    static func nativeMode(for displayID: CGDirectDisplayID) -> ScreenMode? {
        modes(for: displayID)
            .filter { $0.isNativeTiming }
            .max { a, b in (a.pixelWidth, a.refreshRate) < (b.pixelWidth, b.refreshRate) }
    }

    private static func rawModes(for displayID: CGDirectDisplayID) -> [CGDisplayMode] {
        (CGDisplayCopyAllDisplayModes(displayID, listOptions) as? [CGDisplayMode]) ?? []
    }

    private static func rawMode(id: Int32, on displayID: CGDirectDisplayID) -> CGDisplayMode? {
        rawModes(for: displayID).first { $0.ioDisplayModeID == id }
    }

    /// Finds the closest live mode to a stored fingerprint. Used when restoring a
    /// profile, because IODisplayModeIDs are reshuffled on reconnect.
    static func match(
        _ fingerprint: ScreenMode.Fingerprint,
        on displayID: CGDirectDisplayID
    ) -> ScreenMode? {
        let candidates = modes(for: displayID)
        if let exact = candidates.first(where: { $0.fingerprint == fingerprint }) {
            return exact
        }
        // Same pixels, different refresh: prefer a native timing, then the closest rate.
        let samePixels = candidates.filter {
            $0.pixelWidth == fingerprint.pixelWidth
                && $0.pixelHeight == fingerprint.pixelHeight
                && $0.width == fingerprint.width
        }
        return samePixels.min { a, b in
            if a.isNativeTiming != b.isNativeTiming { return a.isNativeTiming }
            let da = abs(a.refreshRate - Double(fingerprint.refreshRate))
            let db = abs(b.refreshRate - Double(fingerprint.refreshRate))
            return da < db
        }
    }

    // MARK: Applying

    enum Persistence {
        /// Lives until logout. Safe for experimenting.
        case session
        /// Written into the window server's saved configuration. This is what
        /// overwrites a bad remembered arrangement, e.g. the clamshell one.
        case permanent

        var cgOption: CGConfigureOption { self == .session ? .forSession : .permanently }
    }

    struct Request {
        let displayID: CGDirectDisplayID
        let mode: ScreenMode
    }

    @discardableResult
    static func apply(
        _ mode: ScreenMode,
        to displayID: CGDirectDisplayID,
        persistence: Persistence = .permanent
    ) async -> Bool {
        await apply([Request(displayID: displayID, mode: mode)], persistence: persistence)
    }

    /// Applies several mode changes at once.
    ///
    /// When every mode is one CoreGraphics listed, they go through a single
    /// `CGDisplayConfiguration` transaction — restoring a profile display by
    /// display makes the desktop relayout repeatedly and can strand windows
    /// off-screen. A mode only SkyLight knows about cannot join that transaction,
    /// so those are set individually.
    @discardableResult
    static func apply(
        _ requests: [Request],
        persistence: Persistence = .permanent
    ) async -> Bool {
        guard !requests.isEmpty else { return true }

        if requests.allSatisfy({ $0.mode.source == .coreGraphics }),
           await applyTransaction(requests, persistence: persistence) {
            return true
        }

        return await applyIndividually(requests)
    }

    private static func applyTransaction(
        _ requests: [Request],
        persistence: Persistence
    ) async -> Bool {
        await Watchdog.run(seconds: 12, fallback: false) {
            var config: CGDisplayConfigRef?
            guard CGBeginDisplayConfiguration(&config) == .success, let config else {
                Log.display.error("CGBeginDisplayConfiguration failed")
                return false
            }

            for request in requests {
                guard let raw = rawMode(id: request.mode.id, on: request.displayID) else {
                    Log.display.error(
                        "mode \(request.mode.id) not present on display \(request.displayID)"
                    )
                    CGCancelDisplayConfiguration(config)
                    return false
                }
                let result = CGConfigureDisplayWithDisplayMode(config, request.displayID, raw, nil)
                guard result == .success else {
                    Log.display.error(
                        "CGConfigureDisplayWithDisplayMode failed (\(result.rawValue)) for \(request.displayID)"
                    )
                    CGCancelDisplayConfiguration(config)
                    return false
                }
            }

            let complete = CGCompleteDisplayConfiguration(config, persistence.cgOption)
            guard complete == .success else {
                Log.display.error("CGCompleteDisplayConfiguration failed (\(complete.rawValue))")
                return false
            }
            return true
        }
    }

    /// SkyLight path. Note it always writes the window server's saved state — it
    /// has no session-only option — so `Persistence` does not apply here.
    private static func applyIndividually(_ requests: [Request]) async -> Bool {
        await Watchdog.run(seconds: 10, fallback: false) {
            var allSucceeded = true
            for request in requests {
                if !SkyLightModes.apply(modeNumber: request.mode.id, to: request.displayID) {
                    allSucceeded = false
                }
            }
            return allSucceeded
        }
    }
}
