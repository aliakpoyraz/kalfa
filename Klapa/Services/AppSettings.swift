import Foundation
import Observation

/// User preferences, backed by `UserDefaults`.
@MainActor
@Observable
final class AppSettings {

    private enum Key {
        static let autoApplyProfiles = "autoApplyProfiles"
        static let persistModeChanges = "persistModeChanges"
        static let showHiddenModes = "showHiddenModes"
        static let showLowResolutionTwins = "showLowResolutionTwins"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.autoApplyProfiles: true,
            Key.persistModeChanges: true,
            Key.showHiddenModes: false,
            Key.showLowResolutionTwins: false,
        ])
    }

    /// Re-apply a matching profile whenever the set of connected panels changes.
    var autoApplyProfiles: Bool {
        get { defaults.bool(forKey: Key.autoApplyProfiles) }
        set { defaults.set(newValue, forKey: Key.autoApplyProfiles) }
    }

    /// Write mode changes into the window server's saved configuration rather than
    /// only for this login session. Needed for a change to survive a reboot — and
    /// to overwrite a bad remembered arrangement.
    var persistModeChanges: Bool {
        get { defaults.bool(forKey: Key.persistModeChanges) }
        set { defaults.set(newValue, forKey: Key.persistModeChanges) }
    }

    /// Include modes macOS marks "never show". They are usually unsafe timings.
    var showHiddenModes: Bool {
        get { defaults.bool(forKey: Key.showHiddenModes) }
        set { defaults.set(newValue, forKey: Key.showHiddenModes) }
    }

    /// Include the non-HiDPI twin of each scaled resolution. Off by default
    /// because on a Retina setup these are the modes you never want.
    var showLowResolutionTwins: Bool {
        get { defaults.bool(forKey: Key.showLowResolutionTwins) }
        set { defaults.set(newValue, forKey: Key.showLowResolutionTwins) }
    }
}
