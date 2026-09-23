import AppKit
import ColorSync
import CoreGraphics
import Foundation
import KalfaUI

/// A display that is online right now, plus the identity Kalfa uses to recognise
/// it again after it is unplugged and replugged.
///
/// `CGDirectDisplayID` is recycled by the window server and must never be
/// persisted. The UUID from `CGDisplayCreateUUIDFromDisplayID` is stable for the
/// physical panel, so profiles are keyed on that.
struct ScreenInfo: Identifiable, Hashable {

    let displayID: CGDirectDisplayID
    /// Stable panel identity. Same string macOS writes into its own display plists.
    let uuid: String
    /// Human name, e.g. `MAG 274QF` or `Built-in Liquid Retina XDR Display`.
    let name: String
    let isBuiltIn: Bool
    let isMain: Bool
    /// Non-nil when this display is mirroring another one.
    let mirrorSource: CGDirectDisplayID?
    let vendorID: UInt32
    let modelID: UInt32
    let serialNumber: UInt32
    /// Top-left corner in the global desktop coordinate space.
    let origin: CGPoint

    var id: String { uuid }

    var isMirrored: Bool { mirrorSource != nil }

    /// Displays that can speak DDC/CI. The internal panel never can.
    var supportsDDC: Bool { !isBuiltIn && !isMirrored }

    // MARK: Enumeration

    /// Every online display, main first, then built-in, then by position.
    static func online() -> [ScreenInfo] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }

        let names = localizedNames()

        return ids.prefix(Int(count)).map { id in
            let mirror = CGDisplayMirrorsDisplay(id)
            let bounds = CGDisplayBounds(id)
            return ScreenInfo(
                displayID: id,
                uuid: Self.uuid(for: id) ?? "display-\(id)",
                name: names[id] ?? fallbackName(for: id),
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                isMain: CGDisplayIsMain(id) != 0,
                mirrorSource: mirror == kCGNullDirectDisplay ? nil : mirror,
                vendorID: CGDisplayVendorNumber(id),
                modelID: CGDisplayModelNumber(id),
                serialNumber: CGDisplaySerialNumber(id),
                origin: bounds.origin
            )
        }
        .sorted { a, b in
            if a.isMain != b.isMain { return a.isMain }
            if a.isBuiltIn != b.isBuiltIn { return a.isBuiltIn }
            if a.origin.x != b.origin.x { return a.origin.x < b.origin.x }
            return a.origin.y < b.origin.y
        }
    }

    /// Stable UUID string for a display, or nil if the window server declines.
    static func uuid(for displayID: CGDirectDisplayID) -> String? {
        guard let ref = CGDisplayCreateUUIDFromDisplayID(displayID) else { return nil }
        let cf = ref.takeRetainedValue()
        return CFUUIDCreateString(nil, cf) as String?
    }

    /// Resolves a stored UUID back to a live display ID, if that panel is connected.
    static func displayID(forUUID uuid: String) -> CGDirectDisplayID? {
        guard let cf = CFUUIDCreateFromString(nil, uuid as CFString) else { return nil }
        let id = CGDisplayGetDisplayIDFromUUID(cf)
        return id == kCGNullDirectDisplay ? nil : id
    }

    // MARK: Names

    /// `NSScreen.localizedName` carries the EDID product name. Map it by screen number.
    private static func localizedNames() -> [CGDirectDisplayID: String] {
        var map: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { continue }
            map[CGDirectDisplayID(number.uint32Value)] = screen.localizedName
        }
        return map
    }

    /// Offline or mirrored displays are absent from `NSScreen.screens`.
    private static func fallbackName(for id: CGDirectDisplayID) -> String {
        CGDisplayIsBuiltin(id) != 0 ? L10n.t("display.builtIn") : L10n.t("display.unnamed", id)
    }
}

// MARK: - Display set signature

/// Identifies a *layout* — which panels are connected together — the same way
/// macOS keys its own per-arrangement display settings.
///
/// Lid open (built-in + external) and clamshell (external alone) are two
/// different signatures, which is exactly why macOS can hold a good mode for one
/// and a bad mode for the other.
struct DisplaySetKey: Hashable, Codable, CustomStringConvertible {
    let uuids: [String]

    init(_ screens: [ScreenInfo]) {
        uuids = screens.map(\.uuid).sorted()
    }

    init(uuids: [String]) {
        self.uuids = uuids.sorted()
    }

    var description: String { uuids.joined(separator: "+") }
}
