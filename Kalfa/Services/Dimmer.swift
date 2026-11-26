import AppKit
import CoreGraphics

/// Darkens the picture itself, for when the backlight is already as low as it
/// goes.
///
/// Two ways to do it, because neither is right everywhere:
///
/// - **Gamma** scales the display's transfer table. It dims everything including
///   the pointer, costs nothing to composite and never shows up in a screenshot.
///   The window server owns the table and hands it back to ColorSync the moment
///   this process exits, so a crash cannot leave the screen dark.
/// - **Overlay** is a black, click-through window above everything. It is the
///   fallback for setups where the table is ignored; the pointer stays bright.
///
/// `factor` is the share of the signal that is let through: 1 is untouched.
@MainActor
enum Dimmer {

    private struct Table {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
    }

    private static let sampleCount = 256

    /// The table as ColorSync left it, per panel UUID. Read once, before the
    /// first change, and kept for the life of the process: reading it again
    /// later would return our own darkened copy and the next write would
    /// compound it.
    private static var baselines: [String: Table] = [:]
    private static var gammaDimmed: Set<String> = []
    private static var covers: [String: NSWindow] = [:]

    static func apply(_ factor: Double, to screen: ScreenInfo, method: BrightnessService.Method) {
        switch method {
        case .gamma:
            removeCover(screen.uuid)
            applyGamma(factor, screen)
        case .overlay:
            restoreGamma(screen)
            applyCover(factor, screen)
        }
    }

    /// Hands every display back untouched. Does not forget the baselines.
    static func clearAll(screens: [ScreenInfo]) {
        for screen in screens { restoreGamma(screen) }
        gammaDimmed.removeAll()
        for uuid in Array(covers.keys) { removeCover(uuid) }
    }

    /// The emergency exit: whatever state the tables are in, put back what the
    /// colour profiles say.
    static func restoreSystemDefaults() {
        CGDisplayRestoreColorSyncSettings()
        gammaDimmed.removeAll()
        for uuid in Array(covers.keys) { removeCover(uuid) }
    }

    // MARK: Gamma

    private static func applyGamma(_ factor: Double, _ screen: ScreenInfo) {
        guard factor < 0.999 else {
            restoreGamma(screen)
            return
        }
        guard let base = baselines[screen.uuid] ?? readTable(screen.displayID) else { return }
        baselines[screen.uuid] = base
        write(base, scaledBy: factor, to: screen.displayID)
        gammaDimmed.insert(screen.uuid)
    }

    private static func restoreGamma(_ screen: ScreenInfo) {
        guard gammaDimmed.remove(screen.uuid) != nil, let base = baselines[screen.uuid] else { return }
        write(base, scaledBy: 1, to: screen.displayID)
    }

    private static func readTable(_ displayID: CGDirectDisplayID) -> Table? {
        var count: UInt32 = 0
        var red = [CGGammaValue](repeating: 0, count: sampleCount)
        var green = red
        var blue = red
        guard CGGetDisplayTransferByTable(displayID, UInt32(sampleCount), &red, &green, &blue, &count) == .success,
              count > 1
        else { return nil }
        let used = Int(count)
        return Table(red: Array(red.prefix(used)), green: Array(green.prefix(used)), blue: Array(blue.prefix(used)))
    }

    private static func write(_ table: Table, scaledBy factor: Double, to displayID: CGDirectDisplayID) {
        let scale = CGGammaValue(factor)
        let red = table.red.map { $0 * scale }
        let green = table.green.map { $0 * scale }
        let blue = table.blue.map { $0 * scale }
        CGSetDisplayTransferByTable(displayID, UInt32(red.count), red, green, blue)
    }

    // MARK: Overlay

    private static func applyCover(_ factor: Double, _ screen: ScreenInfo) {
        guard factor < 0.999, let target = nsScreen(for: screen.displayID) else {
            removeCover(screen.uuid)
            return
        }
        let window = covers[screen.uuid] ?? makeCover()
        covers[screen.uuid] = window
        window.setFrame(target.frame, display: false)
        window.alphaValue = CGFloat(1 - factor)
        window.orderFrontRegardless()
    }

    private static func makeCover() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.hasShadow = false
        window.backgroundColor = .black
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // Kept out of screenshots and screen sharing: the darkness is for the
        // eyes in front of the panel, not for whoever is on the call.
        window.sharingType = .none
        return window
    }

    private static func removeCover(_ uuid: String) {
        covers.removeValue(forKey: uuid)?.close()
    }

    private static func nsScreen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == displayID
        }
    }
}
