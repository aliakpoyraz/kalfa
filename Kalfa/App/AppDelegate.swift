import AppKit
import EzDPIKit
import KalfaUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var signalSources: [DispatchSourceSignal] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        // `Kalfa.app/Contents/MacOS/Kalfa --dump` prints what the window server
        // currently reports and exits. Useful when a display misbehaves and you
        // want the mode list without clicking through the menu.
        if CommandLine.arguments.contains("--dump") {
            Diagnostics.dump()
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock tile, no main window. LSUIElement covers the
        // Dock, this covers being launched by double-click.
        NSApp.setActivationPolicy(.accessory)

        EzDPI.setLanguage(turkish: L10n.language.prefersTurkish)
        EzDPI.showSettings = { KalfaWindow.show(.dpi) }
        EzDPI.start()
        installSignalHandlers()
        registerHotkeys()
    }

    /// `ezdpi://on | off | auto | relaunch?bundle=<id>` drives the DPI half, and
    /// `kalfa://window?section=<name>` opens the window on a given page — from
    /// Shortcuts, Raycast or a shell script.
    ///
    /// The scheme was registered for both names from the start but only ever
    /// answered the DPI half; now that the window is where everything lives, it
    /// is worth being able to ask for a page by name without aiming at the menu
    /// bar.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "kalfa", url.host == "window" {
                let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "section" })?.value
                MainActor.assumeIsolated {
                    KalfaWindow.show(raw.flatMap(KalfaWindow.Section.init(rawValue:)) ?? .displays)
                }
                continue
            }
            EzDPI.handle(url: url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Order matters: presentation mode put the Dock and the desktop the way
        // they are, and leaving them hidden after a quit looks like a broken Mac.
        PresentationMode.shared.stop()
        EzDPI.shutdown()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// What each shortcut does. Installed once and kept for the life of the app;
    /// re-binding a key in the panel swaps the combination, not the handler.
    @MainActor
    private func registerHotkeys() {
        let hotkeys = HotkeyService.shared
        hotkeys.install(.commandPalette) { CommandPalette.shared.toggle() }
        hotkeys.install(.muteInput) { AudioService.shared.toggleInputMute() }
        hotkeys.install(.tileLeft) { WindowService.place(.left) }
        hotkeys.install(.tileRight) { WindowService.place(.right) }
        hotkeys.install(.tileTop) { WindowService.place(.top) }
        hotkeys.install(.tileBottom) { WindowService.place(.bottom) }
        hotkeys.install(.tileCenter) { WindowService.place(.center) }
        hotkeys.install(.tileFull) { WindowService.place(.full) }
    }

    /// Quitting from the menu runs `applicationWillTerminate`, but a `launchctl
    /// kill` or a Ctrl-C in a terminal does not — and leaving without restoring
    /// the system proxy leaves the machine pointed at a dead port with no
    /// internet, which is the one failure state the user cannot debug.
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { EzDPI.shutdown() }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
