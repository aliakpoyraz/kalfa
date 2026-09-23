import EzDPIKit
import SwiftUI

@main
struct KalfaApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var center = DisplayCenter.shared
    @State private var scroll = ScrollService.shared
    /// Mirrors the DPI engine's running state so the menu bar icon can show it.
    @StateObject private var dpi = EzDPIStatus()
    /// Read here so a mute from the keyboard shows up in the menu bar at once.
    private let audio = AudioService.shared

    var body: some Scene {
        // One scene. The window is AppKit-owned (`KalfaWindow`) because it is
        // opened from the palette, a hotkey and a `kalfa://` URL — none of which
        // have a SwiftUI environment to call `openWindow` from.
        MenuBarExtra {
            RootView()
                .environment(center)
                .environment(scroll)
        } label: {
            // The app's own mark, not a system glyph: the menu bar is where people
            // recognise Kalfa, and a stock `display` symbol is the same picture a
            // dozen other utilities use. The badges stay as symbols — they are
            // status, not identity, and only appear while that state is live.
            HStack(spacing: 2) {
                Image("MenuBarIcon")
                if center.isClamshell {
                    Image(systemName: "macbook.and.iphone")
                }
                if audio.isInputMuted {
                    Image(systemName: "mic.slash.fill")
                }
                if dpi.isActive {
                    Image(systemName: "lock.shield.fill")
                }
            }
            .accessibilityLabel("Kalfa")
        }
        .menuBarExtraStyle(.window)
    }
}
