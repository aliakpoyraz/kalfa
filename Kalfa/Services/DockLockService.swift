import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Observation
import os

/// Decides which display the Dock lives on.
///
/// macOS moves the Dock to whichever display the pointer presses against the
/// Dock edge of — a firm push, not a touch. With a laptop under an external
/// monitor that edge is the laptop's bottom, which is exactly where the
/// pointer ends up when it is pushed down, and turning off "Displays have
/// separate Spaces" no longer stops it.
///
/// Three modes:
/// - `off` leaves macOS alone;
/// - `main` drops pointer events in a thin band along the Dock edge of every
///   other display, so the Dock never sees the pointer arrive there;
/// - `touch` moves the Dock as soon as the pointer touches a display's Dock
///   edge, no push needed.
///
/// Kalfa never moves the pointer itself: the Dock only changes display when
/// the person takes the pointer to an edge.
@MainActor
@Observable
final class DockLockService {

    enum Mode: String, CaseIterable {
        case off, main, touch
    }

    private static let modeKey = "dockMode"
    /// The 1.0 switch, read once to carry an enabled lock over to `main`.
    private static let legacyEnabledKey = "dockLockEnabled"

    private(set) var isRunning = false
    private(set) var isTrusted = AXIsProcessTrusted()

    /// Stored for the same reason as `ScrollService.isEnabled`: `@Observable`
    /// only tracks stored properties.
    var mode: Mode {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: Self.modeKey)
            if isEnabled { start() } else { stop() }
        }
    }

    var isEnabled: Bool { mode != .off }

    private let defaults: UserDefaults
    private let engine = DockLockEngine()
    private var trustPoll: Task<Void, Never>?
    private var screenObserver: (any NSObjectProtocol)?
    private var dockObserver: (any NSObjectProtocol)?

    @MainActor static let shared = DockLockService()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.modeKey), let saved = Mode(rawValue: raw) {
            mode = saved
        } else {
            mode = defaults.bool(forKey: Self.legacyEnabledKey) ? .main : .off
        }
        engine.onEdgeTouch = { display, point in
            Task { @MainActor in DockLockService.shared.edgeTouched(display: display, at: point) }
        }
        observeChanges()
        if isEnabled { start() }
    }

    /// Steps through the modes in the order the home tile shows them.
    func cycleMode() {
        let all = Mode.allCases
        mode = all[((all.firstIndex(of: mode) ?? 0) + 1) % all.count]
    }

    func start() {
        isTrusted = AXIsProcessTrusted()
        guard isTrusted else {
            Log.dock.notice("start: not trusted, polling")
            isRunning = false
            pollForTrust()
            return
        }
        arm()
    }

    func stop() {
        // Disarmed, not removed: creating a tap is what re-raises the
        // permission alert (see `ScrollService.stop`).
        engine.setArmed(false)
        isRunning = false
        trustPoll?.cancel()
        trustPoll = nil
    }

    func requestPermission() {
        isTrusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if isTrusted {
            if isEnabled { start() }
        } else {
            pollForTrust()
        }
    }

    // MARK: Geometry

    enum Edge: String { case bottom, left, right }

    /// Where the Dock sits. Read on every layout change rather than cached: it
    /// can be moved from System Settings while Kalfa runs.
    static var dockEdge: Edge {
        Edge(rawValue: UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "") ?? .bottom
    }

    /// Global display coordinates: origin at the main display's top left,
    /// y growing downward, same as the events.
    private static func displays() -> [(id: CGDirectDisplayID, bounds: CGRect)] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids
            .filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .map { ($0, CGDisplayBounds($0)) }
    }

    /// Every display's Dock edge. Where another display continues past it the
    /// pointer crosses over instead of pressing, so the engine checks the
    /// point itself is not a doorway (`DockLockEngine.Zone.isWall`).
    static func zones(for mode: Mode) -> [DockLockEngine.Zone] {
        let all = displays()
        guard all.count > 1, mode != .off else { return [] }
        let main = CGMainDisplayID()
        let edge = dockEdge
        return all.compactMap { id, bounds in
            // In `main` only the other displays are fenced; in `touch` every
            // display's edge is a trigger.
            if mode == .main && id == main { return nil }
            return DockLockEngine.Zone(
                display: id,
                bounds: bounds,
                edge: edge,
                others: all.filter { $0.id != id }.map(\.bounds)
            )
        }
    }

    /// Which display the Dock is on now, read from its accessibility tree.
    /// `nil` when it cannot be told (Dock hidden, no permission).
    static func currentDockDisplay() -> CGDirectDisplayID? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children) == .success,
              let list = (children as? [AXUIElement])?.first else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(list, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &origin) else { return nil }
        var size = CGSize.zero
        var sizeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(list, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let sizeValue, CFGetTypeID(sizeValue) == AXValueGetTypeID() {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }
        let centre = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        return displays().first { $0.bounds.contains(centre) }?.id
    }

    // MARK: Internals

    /// `touch` mode: the pointer reached a display's Dock edge. If the Dock is
    /// elsewhere, the push macOS wants is supplied where the pointer already
    /// is — the pointer itself does not move.
    private func edgeTouched(display: CGDirectDisplayID, at point: CGPoint) {
        guard mode == .touch, isRunning else { return }
        let current = Self.currentDockDisplay()
        Log.dock.notice("edge touched on \(display), dock on \(current ?? 0)")
        guard current != display else { return }
        engine.press(at: point, edge: Self.dockEdge)
    }

    private func arm() {
        engine.setZones(Self.zones(for: mode), dropping: mode == .main)
        isRunning = engine.install()
        engine.setArmed(isRunning)
        Log.dock.notice("armed: mode=\(self.mode.rawValue, privacy: .public), tap running=\(self.isRunning), zones=\(Self.zones(for: self.mode).count)")
    }

    private func observeChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // The Dock posts this when its preferences change, orientation included.
        dockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.dock.prefchanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        guard isRunning else { return }
        engine.setZones(Self.zones(for: mode), dropping: mode == .main)
    }

    private func pollForTrust() {
        guard trustPoll == nil else { return }
        trustPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                guard self.isEnabled else { break }
                if AXIsProcessTrusted() {
                    isTrusted = true
                    arm()
                    break
                }
            }
            self?.trustPoll = nil
        }
    }
}

// MARK: - Engine

/// The pointer tap, on its own thread for the same reason as the scroll engine:
/// a tap that waits on a busy main thread is torn down by the system.
///
/// A session tap that only ever passes or drops events. It never warps the
/// pointer and never calls into the window server from the callback: a tap
/// callback that does is waiting on the window server while the window server
/// waits on it, and every display freezes.
final class DockLockEngine: @unchecked Sendable {

    struct Zone: Sendable {
        let display: CGDirectDisplayID
        let bounds: CGRect
        let edge: DockLockService.Edge
        /// The other displays, to tell a doorway from a wall.
        let others: [CGRect]

        /// Whether the pointer at `p` sits against a wall — nothing past the
        /// edge right there to cross into.
        func isWall(at p: CGPoint) -> Bool {
            let past: CGPoint
            switch edge {
            case .bottom: past = CGPoint(x: p.x, y: bounds.maxY + 0.5)
            case .left: past = CGPoint(x: bounds.minX - 0.5, y: p.y)
            case .right: past = CGPoint(x: bounds.maxX + 0.5, y: p.y)
            }
            return !others.contains { $0.contains(past) }
        }

        /// Distance from the Dock edge, or nil when `p` is on another display.
        func depth(of p: CGPoint) -> CGFloat? {
            guard p.x >= bounds.minX, p.x < bounds.maxX, p.y >= bounds.minY, p.y < bounds.maxY else { return nil }
            switch edge {
            case .bottom: return bounds.maxY - 1 - p.y
            case .left: return p.x - bounds.minX
            case .right: return bounds.maxX - 1 - p.x
            }
        }
    }

    /// Depth of the band along a fenced edge in which pointer events are
    /// dropped. Fast flicks skip several points per event; a band this deep
    /// still catches them before the edge.
    private static let band: CGFloat = 10
    /// How close to the edge counts as touching it in `touch` mode.
    private static let touch: CGFloat = 1

    /// Marks Kalfa's own synthetic events so the tap lets them through.
    private static let marker: Int64 = 0x4B414C4641

    /// Called on the tap thread when the pointer touches a Dock edge; must
    /// hand off at once.
    var onEdgeTouch: (@Sendable (CGDirectDisplayID, CGPoint) -> Void)?

    private struct State {
        var zones: [Zone] = []
        var dropping = false
        var lastTouch = Date.distantPast
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let pressing = OSAllocatedUnfairLock(initialState: false)
    private var tap: CFMachPort?
    private var thread: Thread?
    private var timeouts = 0

    func setZones(_ zones: [Zone], dropping: Bool) {
        state.withLock {
            $0.zones = zones
            $0.dropping = dropping
        }
    }

    func install() -> Bool {
        if thread != nil { return tap != nil }
        let created = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else { created.signal(); return }
            let installed = installTap()
            created.signal()
            guard installed else { return }
            CFRunLoopRun()
        }
        thread.name = "com.aliakpoyraz.kalfa.docklock"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread

        created.wait()
        guard tap != nil else {
            self.thread = nil
            Log.dock.error("event tap could not be created")
            return false
        }
        return true
    }

    func setArmed(_ armed: Bool) {
        guard let tap else { return }
        timeouts = 0
        CGEvent.tapEnable(tap: tap, enable: armed)
    }

    /// Supplies the firm push macOS waits for, right where the pointer already
    /// is: a short run of pointer events on the same spot. The pointer does
    /// not move.
    func press(at point: CGPoint, edge: DockLockService.Edge) {
        guard pressing.withLock({ busy in
            if busy { return false }
            busy = true
            return true
        }) else { return }

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            defer { pressing.withLock { $0 = false } }
            let source = CGEventSource(stateID: .hidSystemState)
            for _ in 0..<12 {
                guard let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                          mouseCursorPosition: point, mouseButton: .left) else { return }
                // A push, not a rest: the pointer is pinned at the edge but
                // still trying to travel past it, which is what macOS reads.
                switch edge {
                case .bottom: event.setIntegerValueField(.mouseEventDeltaY, value: 4)
                case .left: event.setIntegerValueField(.mouseEventDeltaX, value: -4)
                case .right: event.setIntegerValueField(.mouseEventDeltaX, value: 4)
                }
                event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
                event.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.025)
            }
        }
    }

    private func installTap() -> Bool {
        // Moves only: dropping drags would stutter a window dragged along the
        // laptop's bottom, and the Dock does not move on a drag.
        let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<DockLockEngine>.fromOpaque(userInfo).takeUnretainedValue()
            return engine.handle(type: type, event: event)
        }
        // Session level, not HID: the Dock reads the pointer from the session
        // stream, so dropping events here is enough, and a session tap that
        // stalls cannot take the hardware cursor down with it.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: false)
        self.tap = tap
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // A tap that keeps timing out stalls the pointer for everyone;
            // after a few, stay off.
            timeouts += 1
            if timeouts <= 3, let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                Log.dock.error("event tap kept timing out, leaving it disabled")
            }
            return Unmanaged.passUnretained(event)
        }

        // Kalfa's own press: let it reach the Dock untouched.
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker {
            return Unmanaged.passUnretained(event)
        }

        let p = event.location
        let (zones, dropping) = state.withLock { ($0.zones, $0.dropping) }
        for zone in zones {
            guard let depth = zone.depth(of: p) else { continue }
            if dropping {
                return depth < Self.band && zone.isWall(at: p) ? nil : Unmanaged.passUnretained(event)
            }
            if depth < Self.touch, zone.isWall(at: p) {
                // Once per touch, not once per event while the pointer rests there.
                let fire = state.withLock { s in
                    guard Date().timeIntervalSince(s.lastTouch) > 1 else { return false }
                    s.lastTouch = Date()
                    return true
                }
                if fire { onEdgeTouch?(zone.display, p) }
            }
            break
        }
        return Unmanaged.passUnretained(event)
    }
}
