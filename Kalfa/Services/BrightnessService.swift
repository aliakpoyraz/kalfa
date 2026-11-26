import AppKit
import CoreGraphics
import Foundation
import Observation
import KalfaUI

/// One brightness scale for every display, whatever drives its backlight.
///
/// The scale runs from `lowest` to 100. From 0 up it is the panel's own
/// backlight — through the system for the built-in display, over DDC for a
/// monitor. Below zero the backlight is already at its minimum and the picture
/// is darkened instead (`Dimmer`), which is how a display gets dimmer than its
/// own menu allows. A monitor that answers neither route still gets a slider:
/// its whole range is the darkening.
///
/// There is a floor. However far down the slider goes, `floor` of the signal is
/// always let through, so the screen never reaches a black the user cannot find
/// their way back from.
@MainActor
@Observable
final class BrightnessService {

    static let shared = BrightnessService()

    /// Where a display's light is controlled.
    enum Backend: String {
        /// macOS owns the backlight: built-in panel, Apple displays.
        case system
        /// The monitor's own brightness over DDC/CI.
        case ddc
        /// No backlight control at all; only the picture can be darkened.
        case software
    }

    enum Method: String, CaseIterable, Identifiable {
        case gamma, overlay
        var id: String { rawValue }
    }

    /// The bottom of the scale, a third of the way below zero.
    static let lowest = BrightnessScale.lowest
    /// Share of the signal that always gets through.
    static let floorChoices: [Double] = [0.4, 0.3, 0.2]

    private enum Key {
        static let allowsBelowZero = "brightness.allowsBelowZero"
        static let floor = "brightness.floor"
        static let method = "brightness.method"
        /// Darkening below zero for displays with a backlight we control, 0…lowest.
        static let dim = "brightness.dimByUUID"
        /// The whole level for software-only displays, 0…100.
        static let soft = "brightness.softByUUID"
    }

    private(set) var backends: [String: Backend] = [:]
    private(set) var levels: [String: Double] = [:]
    private(set) var allowsBelowZero: Bool
    private(set) var floor: Double
    private(set) var method: Method

    @ObservationIgnored private var screens: [ScreenInfo] = []
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    @ObservationIgnored private var ddcTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var watch: Timer?
    @ObservationIgnored private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.allowsBelowZero: true,
            Key.floor: 0.3,
            Key.method: Method.gamma.rawValue,
        ])
        allowsBelowZero = defaults.bool(forKey: Key.allowsBelowZero)
        floor = defaults.double(forKey: Key.floor)
        method = Method(rawValue: defaults.string(forKey: Key.method) ?? "") ?? .gamma

        // The window server resets transfer tables on wake and on some mode
        // changes, so whatever was dimmed has to be dimmed again.
        let reapply: @Sendable (Notification) -> Void = { _ in
            Task { @MainActor in BrightnessService.shared.reapplySoon() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: reapply)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: reapply)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: reapply)
    }

    // MARK: Reading

    func backend(for screen: ScreenInfo) -> Backend? { backends[screen.uuid] }

    func level(for screen: ScreenInfo) -> Double? { levels[screen.uuid] }

    func range(for screen: ScreenInfo) -> ClosedRange<Double> {
        let reachesBelow = allowsBelowZero && backends[screen.uuid] != .software
        return (reachesBelow ? Self.lowest : 0)...100
    }

    /// Whether anything is being darkened right now.
    var isDimming: Bool {
        screens.contains { factor(for: $0) < 0.999 }
    }

    /// "62", "−20": the level as the slider shows it.
    func label(for screen: ScreenInfo) -> String {
        guard let level = levels[screen.uuid] else { return "" }
        let rounded = Int(level.rounded())
        return rounded < 0 ? "\u{2212}\(-rounded)" : "\(rounded)"
    }

    // MARK: Following the displays

    /// Called whenever the set of displays is rebuilt, and when a panel opens:
    /// finds out who controls each backlight and puts back any darkening.
    func sync(_ list: [ScreenInfo]) {
        screens = list.filter { !$0.isMirrored }
        probeTask?.cancel()
        probeTask = Task { await probe() }
    }

    private func probe() async {
        var nextBackends: [String: Backend] = [:]
        var nextLevels: [String: Double] = [:]
        let dim = stored(Key.dim)
        let soft = stored(Key.soft)

        for screen in screens {
            if let raw = SystemBrightness.get(screen.displayID) {
                nextBackends[screen.uuid] = .system
                nextLevels[screen.uuid] = restored(hardware: percent(fromRaw: raw, screen), dim: dim[screen.uuid])
            } else if screen.supportsDDC, DDCService.shared.isSupported,
                      let reading = await DDCService.shared.read(.brightness, from: screen.displayID) {
                nextBackends[screen.uuid] = .ddc
                nextLevels[screen.uuid] = restored(hardware: Double(reading.percent), dim: dim[screen.uuid])
            } else {
                nextBackends[screen.uuid] = .software
                nextLevels[screen.uuid] = min(max(soft[screen.uuid] ?? 100, 0), 100)
            }
        }

        guard !Task.isCancelled else { return }
        backends = nextBackends
        levels = nextLevels
        reapply()
    }

    private func restored(hardware: Double, dim: Double?) -> Double {
        BrightnessScale.restored(hardware: hardware, savedDim: dim, allowsBelowZero: allowsBelowZero)
    }

    // MARK: Changing

    func setLevel(_ value: Double, for screen: ScreenInfo) {
        let backend = backends[screen.uuid] ?? .software
        let bounds = range(for: screen)
        let level = min(max(value, bounds.lowerBound), bounds.upperBound)
        levels[screen.uuid] = level

        switch backend {
        case .system:
            SystemBrightness.set(screen.displayID, raw(fromPercent: max(level, 0), screen))
        case .ddc:
            scheduleDDC(screen, percent: Int(max(level, 0).rounded()))
        case .software:
            break
        }

        Dimmer.apply(factor(for: screen), to: screen, method: method)
        persist(level, for: screen.uuid, backend)
        updateWatch()
    }

    /// One keyboard step, on the display the pointer is on.
    func step(_ delta: Double) {
        guard let screen = screenUnderPointer(), let level = levels[screen.uuid] else { return }
        setLevel(level + delta, for: screen)
    }

    func setLevelUnderPointer(_ level: Double) {
        guard let screen = screenUnderPointer() else { return }
        setLevel(level, for: screen)
    }

    /// Removes every darkening and leaves the backlights where they are.
    func resetDimming() {
        for screen in screens {
            guard let level = levels[screen.uuid] else { continue }
            if backends[screen.uuid] == .software {
                levels[screen.uuid] = 100
                persist(100, for: screen.uuid, .software)
            } else if level < 0 {
                levels[screen.uuid] = 0
                persist(0, for: screen.uuid, .system)
            }
        }
        Dimmer.restoreSystemDefaults()
        updateWatch()
    }

    func setAllowsBelowZero(_ allowed: Bool) {
        allowsBelowZero = allowed
        defaults.set(allowed, forKey: Key.allowsBelowZero)
        guard !allowed else { return }
        for screen in screens where backends[screen.uuid] != .software {
            if let level = levels[screen.uuid], level < 0 { setLevel(0, for: screen) }
        }
    }

    func setFloor(_ value: Double) {
        floor = value
        defaults.set(value, forKey: Key.floor)
        reapply()
    }

    func setMethod(_ value: Method) {
        guard value != method else { return }
        Dimmer.clearAll(screens: screens)
        method = value
        defaults.set(value.rawValue, forKey: Key.method)
        reapply()
    }

    /// On the way out. The window server would restore the tables by itself, but
    /// doing it here means the screen is back before the menu bar icon is gone.
    func shutdown() {
        watch?.invalidate()
        Dimmer.clearAll(screens: screens)
    }

    // MARK: The darkening

    /// Share of the signal let through for a display at its current level.
    private func factor(for screen: ScreenInfo) -> Double {
        guard let level = levels[screen.uuid] else { return 1 }
        return BrightnessScale.factor(level: level, floor: floor, softwareOnly: backends[screen.uuid] == .software)
    }

    private func reapply() {
        for screen in screens {
            Dimmer.apply(factor(for: screen), to: screen, method: method)
        }
        updateWatch()
    }

    private func reapplySoon() {
        guard isDimming else { return }
        Task { @MainActor in
            // The reset arrives a moment after the notification does.
            try? await Task.sleep(for: .milliseconds(600))
            self.reapply()
        }
    }

    // MARK: Backlight plumbing

    /// The built-in backlight switches off entirely at zero. The scale stops one
    /// fine step above that, so the bottom of the slider is "as dim as the panel
    /// goes", never "off".
    private func minimumRaw(_ screen: ScreenInfo) -> Double {
        screen.isBuiltIn ? 1.0 / 64.0 : 0
    }

    private func raw(fromPercent percent: Double, _ screen: ScreenInfo) -> Double {
        BrightnessScale.raw(fromPercent: percent, minimum: minimumRaw(screen))
    }

    private func percent(fromRaw raw: Double, _ screen: ScreenInfo) -> Double {
        BrightnessScale.percent(fromRaw: raw, minimum: minimumRaw(screen))
    }

    /// DDC is a slow serial bus: a write per slider tick makes monitors stutter
    /// or drop the stream. One write per quiet 80 ms.
    private func scheduleDDC(_ screen: ScreenInfo, percent: Int) {
        ddcTasks[screen.uuid]?.cancel()
        let displayID = screen.displayID
        ddcTasks[screen.uuid] = Task {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            await DDCService.shared.write(.brightness, percent: percent, to: displayID)
        }
    }

    /// While a system-driven display is darkened, the brightness keys still
    /// work on its backlight. Raising it with them should lift the darkening
    /// too, so the backlight is polled — only then, and only every two seconds.
    private func updateWatch() {
        let needed = screens.contains { backends[$0.uuid] == .system && (levels[$0.uuid] ?? 0) < 0 }
        if needed, watch == nil {
            watch = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                Task { @MainActor in BrightnessService.shared.checkBacklight() }
            }
        } else if !needed {
            watch?.invalidate()
            watch = nil
        }
    }

    private func checkBacklight() {
        for screen in screens where backends[screen.uuid] == .system {
            guard let level = levels[screen.uuid], level < 0,
                  let raw = SystemBrightness.get(screen.displayID)
            else { continue }
            let hardware = percent(fromRaw: raw, screen)
            guard hardware > BrightnessScale.bottomTolerance else { continue }
            levels[screen.uuid] = hardware
            persist(hardware, for: screen.uuid, .system)
            Dimmer.apply(1, to: screen, method: method)
        }
        updateWatch()
    }

    private func screenUnderPointer() -> ScreenInfo? {
        let point = NSEvent.mouseLocation
        let hit = NSScreen.screens.first { $0.frame.contains(point) }
        let number = (hit?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        return screens.first { $0.displayID == number } ?? screens.first
    }

    // MARK: Persistence

    private func stored(_ key: String) -> [String: Double] {
        defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    private func persist(_ level: Double, for uuid: String, _ backend: Backend) {
        if backend == .software {
            var soft = stored(Key.soft)
            soft[uuid] = level
            defaults.set(soft, forKey: Key.soft)
        } else {
            var dim = stored(Key.dim)
            dim[uuid] = min(level, 0)
            defaults.set(dim, forKey: Key.dim)
        }
    }
}
