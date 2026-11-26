import AppKit
import Foundation

/// The `defaults write` switches people keep in a notes file.
///
/// Each one reads its current state from the same domain it writes to, so the
/// panel shows what the system actually has — including changes made from a
/// terminal — rather than a remembered guess.
@MainActor
enum SystemTweaks {

    // MARK: Screenshots

    static var screenshotFormat: String {
        get { string("com.apple.screencapture", "type") ?? "png" }
        set {
            write("com.apple.screencapture", "type", newValue)
            restart("SystemUIServer")
        }
    }

    static var screenshotShadow: Bool {
        get { !bool("com.apple.screencapture", "disable-shadow") }
        set {
            write("com.apple.screencapture", "disable-shadow", newValue ? "false" : "true", type: "-bool")
            restart("SystemUIServer")
        }
    }

    static var screenshotFolder: URL {
        let path = string("com.apple.screencapture", "location")
        return URL(fileURLWithPath: (path as NSString?)?.expandingTildeInPath ?? NSHomeDirectory() + "/Desktop")
    }

    static func setScreenshotFolder(_ url: URL) {
        write("com.apple.screencapture", "location", url.path)
        restart("SystemUIServer")
    }

    // MARK: Finder

    static var showsHiddenFiles: Bool {
        get { bool("com.apple.finder", "AppleShowAllFiles") }
        set {
            write("com.apple.finder", "AppleShowAllFiles", newValue ? "true" : "false", type: "-bool")
            restart("Finder")
        }
    }

    static var showsAllExtensions: Bool {
        get { UserDefaults.standard.bool(forKey: "AppleShowAllExtensions") }
        set {
            write("NSGlobalDomain", "AppleShowAllExtensions", newValue ? "true" : "false", type: "-bool")
            restart("Finder")
        }
    }

    // MARK: Dock

    /// The pause before an auto-hidden Dock slides out. macOS ships 0.5 s.
    static var dockIsInstant: Bool {
        get { doubleValue("com.apple.dock", "autohide-delay") == 0 }
        set {
            if newValue {
                write("com.apple.dock", "autohide-delay", "0", type: "-float")
                write("com.apple.dock", "autohide-time-modifier", "0.15", type: "-float")
            } else {
                delete("com.apple.dock", "autohide-delay")
                delete("com.apple.dock", "autohide-time-modifier")
            }
            restart("Dock")
        }
    }

    // MARK: defaults(1)

    // Reads go through CFPreferences, not `defaults read`. It is the same
    // store, including changes made from a terminal, without starting a process
    // every time a view asks what a switch is set to.

    private static func value(_ domain: String, _ key: String) -> Any? {
        CFPreferencesAppSynchronize(domain as CFString)
        return CFPreferencesCopyAppValue(key as CFString, domain as CFString)
    }

    private static func string(_ domain: String, _ key: String) -> String? {
        switch value(domain, key) {
        case let text as String: return text.isEmpty ? nil : text
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    private static func bool(_ domain: String, _ key: String) -> Bool {
        switch value(domain, key) {
        case let number as NSNumber: return number.boolValue
        case let text as String: return ["1", "true", "yes"].contains(text.lowercased())
        default: return false
        }
    }

    private static func doubleValue(_ domain: String, _ key: String) -> Double? {
        switch value(domain, key) {
        case let number as NSNumber: return number.doubleValue
        case let text as String: return Double(text)
        default: return nil
        }
    }

    private static func write(_ domain: String, _ key: String, _ value: String, type: String? = nil) {
        var arguments = ["write", domain, key]
        if let type { arguments.append(type) }
        arguments.append(value)
        _ = run("/usr/bin/defaults", arguments)
    }

    private static func delete(_ domain: String, _ key: String) {
        _ = run("/usr/bin/defaults", ["delete", domain, key])
    }

    /// The setting is written to disk immediately, but the process that reads it
    /// only looks at launch — hence the restart. Finder and Dock come straight
    /// back; nothing is lost.
    private static func restart(_ process: String) {
        _ = run("/usr/bin/killall", [process])
    }

    @discardableResult
    private static func run(_ path: String, _ arguments: [String]) -> String {
        Shell.result(path, arguments)
    }
}
