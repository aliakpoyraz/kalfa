import CoreGraphics
import Foundation

/// Reads the window server's full mode list.
///
/// `CGDisplayCopyAllDisplayModes` returns only modes carrying the IOKit "safe"
/// flag. SkyLight keeps a longer list, and on a clamshell MacBook the modes it
/// withholds are exactly the ones worth having: a 2560×1440 HiDPI mode can be
/// present in SkyLight's list (flags `0x00200001`, density 2.0) while completely
/// absent from the CoreGraphics one, which is why closing the lid drops the
/// desktop to a non-Retina backing store.
///
/// The description struct is undocumented. Its layout has been stable since
/// macOS 11 and the call validates the length it is given, so a wrong size fails
/// loudly instead of returning garbage:
///
/// ```c
/// struct CGSDisplayModeDescription {   // 0xD4 bytes
///     uint32_t modeNumber;             // 0x00  == IODisplayModeID
///     uint32_t flags;                  // 0x04  IOKit mode flags
///     uint32_t width;                  // 0x08  logical points
///     uint32_t height;                 // 0x0C
///     uint32_t depth;                  // 0x10
///     uint32_t _reserved[42];
///     uint16_t _pad;
///     uint16_t refreshRate;            // 0xBE  whole Hz
///     uint8_t  _reserved2[16];
///     float    density;                // 0xD0  1.0 or 2.0
/// };
/// ```
enum SkyLightModes {

    private static let descriptionLength: Int32 = 0xD4

    private enum Offset {
        static let modeNumber = 0x00
        static let flags = 0x04
        static let width = 0x08
        static let height = 0x0C
        static let refreshRate = 0xBE
        static let density = 0xD0
    }

    struct Entry {
        let modeNumber: Int32
        let flags: UInt32
        let width: Int
        let height: Int
        let refreshRate: Double
        let density: Int
    }

    /// Every mode SkyLight knows about for this display, deduplicated by mode number.
    static func entries(for displayID: CGDirectDisplayID) -> [Entry] {
        var count: Int32 = 0
        guard CGSGetNumberOfDisplayModes(displayID, &count) == .success, count > 0 else {
            Log.display.error("CGSGetNumberOfDisplayModes failed for \(displayID)")
            return []
        }

        var buffer = [UInt8](repeating: 0, count: Int(descriptionLength))
        var result: [Entry] = []
        var seen = Set<Int32>()

        for index in 0..<count {
            let status = buffer.withUnsafeMutableBytes { raw -> CGError in
                CGSGetDisplayModeDescriptionOfLength(
                    displayID, index, raw.baseAddress!, descriptionLength
                )
            }
            guard status == .success else { continue }

            let entry = buffer.withUnsafeBytes { raw -> Entry in
                let density = raw.loadUnaligned(fromByteOffset: Offset.density, as: Float.self)
                let rounded = Int(density.rounded())
                return Entry(
                    modeNumber: Int32(
                        bitPattern: raw.loadUnaligned(fromByteOffset: Offset.modeNumber, as: UInt32.self)
                    ),
                    flags: raw.loadUnaligned(fromByteOffset: Offset.flags, as: UInt32.self),
                    width: Int(raw.loadUnaligned(fromByteOffset: Offset.width, as: UInt32.self)),
                    height: Int(raw.loadUnaligned(fromByteOffset: Offset.height, as: UInt32.self)),
                    refreshRate: Double(
                        raw.loadUnaligned(fromByteOffset: Offset.refreshRate, as: UInt16.self)
                    ),
                    // Guard against a layout change turning into a 0× or 97× scale.
                    density: (1...2).contains(rounded) ? rounded : 1
                )
            }

            guard entry.width > 0, entry.height > 0 else { continue }
            guard seen.insert(entry.modeNumber).inserted else { continue }
            result.append(entry)
        }

        return result
    }

    /// Stages a mode inside an open display-configuration transaction.
    ///
    /// Must be called between `CGBeginDisplayConfiguration` and
    /// `CGCompleteDisplayConfiguration`; the config object is what SkyLight
    /// records the change into. Because it takes part in the normal transaction,
    /// a SkyLight-only mode can be applied atomically alongside ordinary ones and
    /// honours the same persistence option.
    @discardableResult
    static func stage(
        modeNumber: Int32,
        for displayID: CGDirectDisplayID,
        in config: CGDisplayConfigRef
    ) -> Bool {
        let error = CGSConfigureDisplayMode(config, displayID, modeNumber)
        if error != .success {
            Log.display.error("CGSConfigureDisplayMode failed (\(error.rawValue)) for \(displayID)")
        }
        return error == .success
    }
}
