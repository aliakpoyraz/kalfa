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

    /// The same resolution and refresh rate at the other backing scale.
    ///
    /// This is what a "HiDPI" switch actually does: the logical desktop size does
    /// not change, only whether it is drawn into a 1× or 2× backing store.
    static func scaleSibling(
        of mode: ScreenMode,
        hiDPI: Bool,
        on displayID: CGDirectDisplayID
    ) -> ScreenMode? {
        let wantedRate = Int(mode.refreshRate.rounded())

        let candidates = modes(for: displayID).filter {
            $0.width == mode.width
                && $0.height == mode.height
                && $0.isHiDPI == hiDPI
                && $0.id != mode.id
        }
        guard !candidates.isEmpty else { return nil }

        // Same refresh rate if it exists, otherwise the fastest available; a
        // publicly-listed mode beats a SkyLight-only one at equal footing.
        return candidates.min { a, b in
            let da = abs(Int(a.refreshRate.rounded()) - wantedRate)
            let db = abs(Int(b.refreshRate.rounded()) - wantedRate)
            if da != db { return da < db }
            if a.isExtended != b.isExtended { return !a.isExtended }
            if a.isNativeTiming != b.isNativeTiming { return a.isNativeTiming }
            return a.refreshRate > b.refreshRate
        }
    }

    /// The fastest, or the most conservative, refresh rate available at the
    /// current resolution and backing scale.
    ///
    /// Backs the "high refresh rate" switch: off means 60 Hz, on means whatever
    /// this panel's ceiling is.
    static func refreshSibling(
        of mode: ScreenMode,
        fastest: Bool,
        on displayID: CGDirectDisplayID
    ) -> ScreenMode? {
        let candidates = modes(for: displayID).filter {
            $0.width == mode.width
                && $0.height == mode.height
                && $0.isHiDPI == mode.isHiDPI
        }
        guard !candidates.isEmpty else { return nil }

        let target: ScreenMode? = fastest
            ? candidates.max(by: isWorseChoice)
            // "Off" is 60 Hz when the panel has it, otherwise its slowest mode.
            : candidates.first { Int($0.refreshRate.rounded()) == 60 }
                ?? candidates.min { $0.refreshRate < $1.refreshRate }

        guard let target, target.id != mode.id else { return nil }
        return target
    }

    /// Ordering used to pick "the best" mode among equals: highest rate first,
    /// then prefer timings macOS vouches for.
    private static func isWorseChoice(_ a: ScreenMode, _ b: ScreenMode) -> Bool {
        if a.refreshRate != b.refreshRate { return a.refreshRate < b.refreshRate }
        if a.isNativeTiming != b.isNativeTiming { return !a.isNativeTiming }
        return a.isExtended && !b.isExtended
    }

    /// The highest refresh rate this display can do at the given mode's
    /// resolution and scale.
    static func peakRefreshRate(for mode: ScreenMode, on displayID: CGDirectDisplayID) -> Double {
        modes(for: displayID)
            .filter { $0.width == mode.width && $0.height == mode.height && $0.isHiDPI == mode.isHiDPI }
            .map(\.refreshRate)
            .max() ?? mode.refreshRate
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

    /// Applies several mode changes as one atomic reconfiguration.
    ///
    /// Modes from either list go into the same `CGDisplayConfiguration`
    /// transaction — a CoreGraphics one through the public setter, a
    /// SkyLight-only one through `CGSConfigureDisplayMode`. Restoring a profile
    /// display by display makes the desktop relayout repeatedly and can strand
    /// windows off-screen, so the transaction is worth keeping intact.
    @discardableResult
    static func apply(
        _ requests: [Request],
        persistence: Persistence = .permanent
    ) async -> Bool {
        guard !requests.isEmpty else { return true }

        return await Watchdog.run(seconds: 12, fallback: false) {
            var config: CGDisplayConfigRef?
            guard CGBeginDisplayConfiguration(&config) == .success, let config else {
                Log.display.error("CGBeginDisplayConfiguration failed")
                return false
            }

            for request in requests {
                guard stage(request, in: config) else {
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

    private static func stage(_ request: Request, in config: CGDisplayConfigRef) -> Bool {
        switch request.mode.source {
        case .skyLight:
            return SkyLightModes.stage(
                modeNumber: request.mode.id, for: request.displayID, in: config
            )

        case .coreGraphics:
            guard let raw = rawMode(id: request.mode.id, on: request.displayID) else {
                Log.display.error(
                    "mode \(request.mode.id) not present on display \(request.displayID)"
                )
                return false
            }
            let result = CGConfigureDisplayWithDisplayMode(config, request.displayID, raw, nil)
            if result != .success {
                Log.display.error(
                    "CGConfigureDisplayWithDisplayMode failed (\(result.rawValue)) for \(request.displayID)"
                )
            }
            return result == .success
        }
    }
}
