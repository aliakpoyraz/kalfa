import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        // `Klapa.app/Contents/MacOS/Klapa --dump` prints what the window server
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
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
