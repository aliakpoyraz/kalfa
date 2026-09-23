import Foundation

/// Carries the old Klapa preferences into Kalfa's own domain.
///
/// Preferences are keyed by bundle identifier, so the rename to
/// `com.aliakpoyraz.kalfa` would otherwise hand a long-time user a factory-fresh
/// app: language back to system, hidden modes hidden again, smooth scrolling off.
/// Profiles survive on their own — they live in Application Support, not here.
///
/// Runs once, and only fills keys the new domain has never been given.
enum DefaultsMigration {

    private static let doneKey = "migratedFromKlapa"
    private static let oldDomain = "com.aliakpoyraz.klapa"
    private static let keys = [
        "language",
        "autoApplyProfiles",
        "persistModeChanges",
        "showHiddenModes",
        "showLowResolutionTwins",
        "smoothScrollEnabled",
    ]

    static func runOnce(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)

        guard let old = UserDefaults(suiteName: oldDomain) else { return }
        for key in keys where defaults.object(forKey: key) == nil {
            guard let value = old.object(forKey: key) else { continue }
            defaults.set(value, forKey: key)
        }
        Log.display.notice("migrated preferences from the Klapa domain")
    }
}
