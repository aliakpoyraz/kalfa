import CoreGraphics
import Foundation

/// What is actually travelling down the cable, and what the GPU is drawing into.
///
/// These two are not the same and people conflate them. A display mode can
/// advertise 8 bits per channel while the framebuffer runs at 10, and the link
/// can then drop to chroma subsampling to carry it. Subsampling is what makes
/// text look soft even at a perfectly matched resolution, and nothing in the
/// resolution picker hints that it is happening.
///
/// Everything here is read-only. SkyLight exports getters for pixel encoding but
/// no setter, and the link format is negotiated by the window server; macOS
/// offers no supported way for an application to choose it.
enum LinkInfo {

    /// How colour is carried over the cable.
    enum ColorFormat: Int {
        case rgb = 0
        case ycbcr444 = 1
        case ycbcr422 = 2
        case ycbcr420 = 3

        var label: String {
            switch self {
            case .rgb: return "RGB"
            case .ycbcr444: return "YCbCr 4:4:4"
            case .ycbcr422: return "YCbCr 4:2:2"
            case .ycbcr420: return "YCbCr 4:2:0"
            }
        }

        /// Formats that throw away colour resolution. Text suffers first.
        var isSubsampled: Bool { self == .ycbcr422 || self == .ycbcr420 }
    }

    struct Link {
        let bitDepth: Int
        let colorFormat: ColorFormat?

        var label: String {
            let color = colorFormat?.label ?? "?"
            return "\(bitDepth)-bit \(color)"
        }
    }

    // MARK: Framebuffer

    /// `SLSGetDisplayPixelEncodingOfLength(display, buffer, length)`.
    ///
    /// Resolved at runtime rather than linked: SkyLight is a private framework
    /// that exists only inside the dyld shared cache, so there is nothing on disk
    /// for the linker to bind against. A missing symbol then degrades to "no
    /// reading available" instead of refusing to launch.
    private typealias PixelEncodingGetter =
        @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<CChar>, Int32) -> Int32

    private static let pixelEncodingGetter: PixelEncodingGetter? = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY
        ) else {
            Log.display.error("SkyLight could not be opened")
            return nil
        }
        guard let symbol = dlsym(handle, "SLSGetDisplayPixelEncodingOfLength") else {
            Log.display.error("SLSGetDisplayPixelEncodingOfLength is missing on this macOS")
            return nil
        }
        return unsafeBitCast(symbol, to: PixelEncodingGetter.self)
    }()

    /// Bits per colour channel the GPU is drawing into.
    ///
    /// The encoding comes back as a channel map such as
    /// `--------RRRRRRRRGGGGGGGGBBBBBBBB`, so counting the red slots is the
    /// reading. A 10-bit framebuffer is what pushes a link into subsampling.
    static func framebufferBitsPerChannel(for displayID: CGDirectDisplayID) -> Int? {
        guard let getter = pixelEncodingGetter else { return nil }

        var buffer = [CChar](repeating: 0, count: 128)
        let status = buffer.withUnsafeMutableBufferPointer { raw -> Int32 in
            getter(displayID, raw.baseAddress!, 128)
        }
        guard status == 0 else { return nil }

        let red = String(cString: buffer).filter { $0 == "R" }.count
        return red > 0 ? red : nil
    }

    // MARK: Link

    /// Reads the link description the window server recorded for the arrangement
    /// currently on screen.
    ///
    /// There is no API for this. The window server writes it into its own
    /// by-host preferences when it saves a configuration, keyed by the same set
    /// of display UUIDs Klapa uses for profiles, so the record for "these exact
    /// panels" is the one to read.
    static func link(for uuid: String, in setKey: DisplaySetKey) -> Link? {
        guard let plist = loadWindowServerPreferences(),
              let configs = (plist["DisplaySets"] as? [String: Any])?["Configs"] as? [[String: Any]]
        else { return nil }

        for config in configs {
            guard let entries = config["DisplayConfig"] as? [[String: Any]] else { continue }
            let uuids = entries.compactMap { $0["UUID"] as? String }
            guard DisplaySetKey(uuids: uuids) == setKey else { continue }
            guard let entry = entries.first(where: { $0["UUID"] as? String == uuid }),
                  let description = entry["LinkDescription"] as? [String: Any]
            else { continue }

            let depth = description["BitDepth"] as? Int ?? 0
            let encoding = description["PixelEncoding"] as? Int
            guard depth > 0 else { return nil }
            return Link(
                bitDepth: depth,
                colorFormat: encoding.flatMap(ColorFormat.init(rawValue:))
            )
        }
        return nil
    }

    private static func loadWindowServerPreferences() -> [String: Any]? {
        let directory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/ByHost", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return nil }

        // Filename carries the machine's hardware UUID, which is not worth
        // resolving separately — there is only ever one matching file.
        guard let name = names.first(where: {
            $0.hasPrefix("com.apple.windowserver.displays.") && $0.hasSuffix(".plist")
        }) else { return nil }

        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: Any]
        else { return nil }
        return plist
    }
}
