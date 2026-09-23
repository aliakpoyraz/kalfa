import CoreGraphics
import Foundation

/// A saved setup — a scene — remembered per *arrangement*.
///
/// The `setKey` is the point of the whole thing: macOS keeps a separate saved
/// configuration for every combination of connected panels, so the setup you
/// carefully chose with the lid open is a different record from the one used when
/// the lid is shut. A profile captures one such combination and can be re-applied
/// whenever that same combination appears.
struct Profile: Codable, Identifiable, Hashable {

    struct Entry: Codable, Hashable {
        /// Stable panel UUID; survives unplugging.
        let displayUUID: String
        /// Remembered for the UI, so a profile is readable when the panel is absent.
        let displayName: String
        /// Resolution + refresh, matched by value rather than by IODisplayModeID.
        let mode: ScreenMode.Fingerprint
        /// DDC brightness 0-100, when it was readable at save time.
        var brightness: Int?
        /// DDC contrast 0-100, when it was readable at save time.
        var contrast: Int?
    }

    let id: UUID
    var name: String
    var setKey: DisplaySetKey
    var entries: [Entry]
    /// Re-apply automatically the next time this exact set of panels appears.
    var autoApply: Bool
    /// Also push the saved DDC values when applying.
    var restoresBrightness: Bool
    /// Scene extras. Each is nil when the scene does not touch that part of the
    /// machine, which is why they are optional rather than defaulted: a scene
    /// that says nothing about sound must not silently move the sound.
    var audioOutputUID: String?
    /// Kept only so the scene reads properly when the device is unplugged.
    var audioOutputName: String?
    /// `EzDPI.Mode` raw value: auto, on or off.
    var dpiMode: String?
    var caffeine: Bool?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        setKey: DisplaySetKey,
        entries: [Entry],
        autoApply: Bool = true,
        restoresBrightness: Bool = false,
        audioOutputUID: String? = nil,
        audioOutputName: String? = nil,
        dpiMode: String? = nil,
        caffeine: Bool? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.setKey = setKey
        self.entries = entries
        self.autoApply = autoApply
        self.restoresBrightness = restoresBrightness
        self.audioOutputUID = audioOutputUID
        self.audioOutputName = audioOutputName
        self.dpiMode = dpiMode
        self.caffeine = caffeine
        self.createdAt = createdAt
    }

    /// Whether this scene reaches past the displays.
    var hasExtras: Bool {
        audioOutputUID != nil || dpiMode != nil || caffeine != nil
    }

    /// Human hint about what this arrangement is, used for default naming.
    var displayCountLabel: String {
        entries.count == 1 ? "Tek ekran" : "\(entries.count) ekran"
    }
}
