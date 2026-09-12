import CoreGraphics
import Foundation

/// One selectable display mode: logical size, backing pixel size, refresh rate,
/// plus the IOKit flags that explain *why* macOS offers it.
///
/// The flags matter more than they look. macOS synthesises modes that are not in
/// the monitor's EDID (bandwidth-limited fallbacks, mirroring-only timings) and
/// silently prefers them after a reconfiguration. Surfacing `isNativeTiming`
/// makes that visible instead of leaving you to guess why the picture changed.
struct ScreenMode: Identifiable, Hashable, Codable {

    // MARK: IOKit mode flags (IOGraphicsTypes.h)

    private enum IOFlag {
        static let safe: UInt32      = 0x0000_0002
        static let `default`: UInt32 = 0x0000_0004
        static let neverShow: UInt32 = 0x0000_0080
        static let stretched: UInt32 = 0x0000_0800
        static let television: UInt32 = 0x0010_0000
        static let native: UInt32    = 0x0200_0000
    }

    /// Where this mode was discovered. Decides how it can be applied.
    enum Source: String, Codable {
        /// Listed by `CGDisplayCopyAllDisplayModes`; applies through the public
        /// display-configuration transaction.
        case coreGraphics
        /// Only in SkyLight's list. CoreGraphics withheld it — usually for lacking
        /// the IOKit "safe" flag — so it can only be set via `CGSConfigureDisplayMode`.
        case skyLight
    }

    /// IODisplayModeID — what `CGConfigureDisplayWithDisplayMode` actually keys on.
    let id: Int32
    /// Logical size in points (what the UI is laid out in).
    let width: Int
    let height: Int
    /// Backing store size in pixels.
    let pixelWidth: Int
    let pixelHeight: Int
    /// Hz. `0` means the display did not report one (common on internal panels).
    let refreshRate: Double
    let ioFlags: UInt32
    let source: Source

    // MARK: Derived

    /// Retina/HiDPI: more backing pixels than points.
    var isHiDPI: Bool { pixelWidth > width }

    /// Backing scale factor, 1 or 2 in practice.
    var scale: Int { width > 0 ? pixelWidth / width : 1 }

    /// Timing came from the monitor's EDID rather than being synthesised by macOS.
    /// A non-native timing at the same resolution is the usual cause of a picture
    /// that "looks wrong" after the lid closes.
    var isNativeTiming: Bool { ioFlags & IOFlag.native != 0 }

    /// macOS considers this mode safe to apply blind.
    var isSafe: Bool { ioFlags & IOFlag.safe != 0 }

    /// Hidden from System Settings; only listed because we asked for duplicates.
    var isHidden: Bool { ioFlags & IOFlag.neverShow != 0 }

    var isStretched: Bool { ioFlags & IOFlag.stretched != 0 }
    var isTelevision: Bool { ioFlags & IOFlag.television != 0 }

    /// Hidden from every normal interface, System Settings included.
    ///
    /// On a clamshell MacBook the HiDPI modes land here, which is the whole
    /// reason the lid-shut desktop looks wrong.
    var isExtended: Bool { source == .skyLight }

    // MARK: Labels

    var resolutionLabel: String { "\(width) × \(height)" }

    var pixelLabel: String { "\(pixelWidth) × \(pixelHeight)" }

    var refreshLabel: String {
        refreshRate > 0 ? "\(Int(refreshRate.rounded())) Hz" : "—"
    }

    /// One-line description used in menus: `2560 × 1440 · 180 Hz · HiDPI`
    var summary: String {
        var parts = [resolutionLabel, refreshLabel]
        if isHiDPI { parts.append("HiDPI") }
        return parts.joined(separator: " · ")
    }

    // MARK: Construction

    init(_ mode: CGDisplayMode) {
        id = mode.ioDisplayModeID
        width = mode.width
        height = mode.height
        pixelWidth = mode.pixelWidth
        pixelHeight = mode.pixelHeight
        refreshRate = mode.refreshRate
        ioFlags = mode.ioFlags
        source = .coreGraphics
    }

    /// SkyLight reports a density rather than a pixel size, so the backing store
    /// is derived from it.
    init(_ entry: SkyLightModes.Entry) {
        id = entry.modeNumber
        width = entry.width
        height = entry.height
        pixelWidth = entry.width * entry.density
        pixelHeight = entry.height * entry.density
        refreshRate = entry.refreshRate
        ioFlags = entry.flags
        source = .skyLight
    }

    /// Matches a mode across reconnects, where IODisplayModeID is not stable.
    /// Two modes are the "same" if they paint the same pixels at the same rate.
    struct Fingerprint: Hashable, Codable {
        let width: Int
        let height: Int
        let pixelWidth: Int
        let pixelHeight: Int
        let refreshRate: Int   // rounded; 59.97 and 60.0 are the same mode to a human
    }

    var fingerprint: Fingerprint {
        Fingerprint(
            width: width,
            height: height,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            refreshRate: Int(refreshRate.rounded())
        )
    }
}

// MARK: - Ordering

extension ScreenMode {
    /// Menu order: biggest logical size first, then highest refresh, HiDPI ahead
    /// of its low-resolution twin, native timings ahead of synthesised ones.
    static func menuOrder(_ a: ScreenMode, _ b: ScreenMode) -> Bool {
        if a.width != b.width { return a.width > b.width }
        if a.height != b.height { return a.height > b.height }
        if a.isHiDPI != b.isHiDPI { return a.isHiDPI }
        if a.refreshRate != b.refreshRate { return a.refreshRate > b.refreshRate }
        if a.isNativeTiming != b.isNativeTiming { return a.isNativeTiming }
        // A publicly-listed mode is the safer of two otherwise identical choices.
        if a.isExtended != b.isExtended { return !a.isExtended }
        return a.id < b.id
    }
}
