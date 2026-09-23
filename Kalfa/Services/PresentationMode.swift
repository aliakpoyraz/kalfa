import AppKit
import Foundation
import Observation

/// One switch for "I am about to share this screen".
///
/// Hides the Dock and the desktop clutter, keeps the machine awake, and can
/// black out the displays nobody is meant to be looking at. Everything it
/// changes is recorded first and put back on the way out.
@MainActor
@Observable
final class PresentationMode {

    static let shared = PresentationMode()

    private(set) var isOn = false

    /// Cover the displays that are not the main one, so a second monitor does not
    /// broadcast whatever was left open on it.
    var blacksOutOtherScreens: Bool {
        didSet {
            defaults.set(blacksOutOtherScreens, forKey: Self.blackoutKey)
            guard isOn else { return }
            blacksOutOtherScreens ? showCovers() : hideCovers()
        }
    }

    private var previousDockAutohide = false
    private var previousDesktopIcons = true
    private var startedCaffeine = false
    private var covers: [NSWindow] = []

    private let defaults: UserDefaults
    private static let blackoutKey = "presentationBlacksOutOtherScreens"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        blacksOutOtherScreens = defaults.bool(forKey: Self.blackoutKey)
    }

    func toggle() {
        isOn ? stop() : start()
    }

    func start() {
        guard !isOn else { return }
        previousDockAutohide = Self.readBool("com.apple.dock", "autohide")
        previousDesktopIcons = Self.readBool("com.apple.finder", "CreateDesktop", default: true)

        Self.write("com.apple.dock", "autohide", true)
        Self.restart("Dock")
        Self.write("com.apple.finder", "CreateDesktop", false)
        Self.restart("Finder")

        if !CaffeineService.shared.isActive {
            CaffeineService.shared.span = .indefinite
            CaffeineService.shared.start()
            startedCaffeine = true
        }

        if blacksOutOtherScreens { showCovers() }
        isOn = true
    }

    func stop() {
        guard isOn else { return }
        Self.write("com.apple.dock", "autohide", previousDockAutohide)
        Self.restart("Dock")
        Self.write("com.apple.finder", "CreateDesktop", previousDesktopIcons)
        Self.restart("Finder")

        // Only released if this mode is what started it; a keep-awake the user
        // turned on themselves is not ours to cancel.
        if startedCaffeine {
            CaffeineService.shared.stop()
            startedCaffeine = false
        }

        hideCovers()
        isOn = false
    }

    // MARK: Blackout

    private func showCovers() {
        hideCovers()
        let main = NSScreen.main
        for screen in NSScreen.screens where screen != main {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.backgroundColor = .black
            window.isOpaque = true
            window.ignoresMouseEvents = true
            // Above everything but the screen saver, and visible no matter which
            // Space is in front — a presentation switches Spaces all the time.
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.orderFrontRegardless()
            covers.append(window)
        }
    }

    private func hideCovers() {
        for window in covers { window.orderOut(nil) }
        covers.removeAll()
    }

    // MARK: defaults(1)

    private static func readBool(_ domain: String, _ key: String, default fallback: Bool = false) -> Bool {
        let output = Shell.result("/usr/bin/defaults", ["read", domain, key])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty { return fallback }
        return ["1", "true", "YES"].contains(output)
    }

    private static func write(_ domain: String, _ key: String, _ value: Bool) {
        _ = Shell.result("/usr/bin/defaults", ["write", domain, key, "-bool", value ? "true" : "false"])
    }

    private static func restart(_ process: String) {
        _ = Shell.result("/usr/bin/killall", [process])
    }
}
