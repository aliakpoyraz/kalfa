import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Observation
import QuartzCore

/// Turns a mouse wheel's discrete detents into continuous pixel scrolling.
///
/// A wheel reports whole lines: every detent makes macOS jump a fixed block of
/// text at once. A trackpad reports pixels, which is why the same document feels
/// smooth under a finger and stuttery under a wheel. Kalfa swallows the wheel
/// event and plays the distance back over the following frames.
///
/// One switch, no tuning: a scroll feel is judged by hand, not by number.
///
/// The behaviour is modelled on Mos (github.com/Caldis/Mos), which is licensed
/// CC BY-NC and therefore could not be borrowed from as code. What was taken is
/// what it does, rewritten here: a floor under the travel of a single detent, a
/// two-stage filter instead of one decay, the original event reposted to the
/// process under the pointer, and no scroll phases at all.
///
/// Trackpads and the Magic Mouse are left alone: their events are already
/// continuous, and re-animating them would fight the driver's own inertia.
@MainActor
@Observable
final class ScrollService {

    private static let enabledKey = "smoothScrollEnabled"

    /// The stored switch position, readable without holding the instance — the
    /// health panel reports on the feature without owning the service.
    static var isEnabledSetting: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Set while the event tap is installed and armed.
    private(set) var isRunning = false
    /// Accessibility permission. Without it macOS refuses to install the tap.
    private(set) var isTrusted = AXIsProcessTrusted()

    /// Stored rather than read straight out of `UserDefaults` on each access:
    /// `@Observable` only tracks stored properties, and a computed one leaves the
    /// switch showing its old position until the panel is reopened.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { start() } else { stop() }
        }
    }

    private let defaults: UserDefaults
    private let engine = ScrollEngine()
    private var trustPoll: Task<Void, Never>?
    private var screenObserver: (any NSObjectProtocol)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        DefaultsMigration.runOnce(defaults: defaults)
        defaults.register(defaults: [Self.enabledKey: false])
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        observeScreenChanges()
        if isEnabled { start() }
    }

    // MARK: Lifecycle

    /// Installs the tap. Silently does nothing without accessibility permission —
    /// `requestPermission()` is what asks for it.
    func start() {
        isTrusted = AXIsProcessTrusted()
        guard isTrusted else {
            isRunning = false
            pollForTrust()
            return
        }
        // The display link has to be built here: NSScreen is main-thread API, and
        // the engine's own thread must not touch it.
        isRunning = engine.install(displayLink: makeDisplayLink())
        engine.setArmed(isRunning)
    }

    func stop() {
        // The tap stays installed and is only disarmed. Creating one is what makes
        // macOS put up its permission alert, and it does so whenever it considers
        // the grant stale — so a switch flipped twice must not create a second one.
        engine.setArmed(false)
        isRunning = false
        trustPoll?.cancel()
        trustPoll = nil
    }

    /// Opens the system prompt. The permission is granted to the *signature*, so
    /// an ad-hoc built Kalfa has to be re-approved after every rebuild.
    func requestPermission() {
        // The constant itself is a mutable global as far as Swift 6 is concerned;
        // its value has been this string since it was introduced.
        isTrusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if isTrusted {
            if isEnabled { start() }
        } else {
            pollForTrust()
        }
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url { NSWorkspace.shared.open(url) }
    }

    // MARK: Internals

    private func makeDisplayLink() -> CADisplayLink? {
        guard let screen = NSScreen.main else { return nil }
        return screen.displayLink(target: engine, selector: #selector(ScrollEngine.step(_:)))
    }

    /// A link keeps the refresh rate it was created with. Wake a display, plug one
    /// in, or change a mode in Kalfa itself and the old link can be left ticking at
    /// 60 Hz in front of a 180 Hz panel — which is stutter that looks exactly like
    /// a bad easing curve. Rebuilding on every layout change avoids the whole
    /// class of it.
    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                self.engine.replaceDisplayLink(self.makeDisplayLink())
            }
        }
    }

    /// Granting accessibility sends no notification, so the only way to start the
    /// moment the user flips the switch in System Settings is to look.
    private func pollForTrust() {
        guard trustPoll == nil else { return }
        trustPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                guard isEnabled else { break }
                if AXIsProcessTrusted() {
                    isTrusted = true
                    isRunning = engine.install(displayLink: makeDisplayLink())
                    engine.setArmed(isRunning)
                    break
                }
            }
            self?.trustPoll = nil
        }
    }
}

// MARK: - Engine

/// The event tap and its playback, on a thread of their own.
///
/// Both halves must stay off the main actor: a tap whose callback waits on a busy
/// main thread gets torn down by the system for timing out, which shows up as the
/// wheel dying mid-scroll. Keeping the tap and the animation on the *same* thread
/// means the scroll state needs no locking at all.
///
/// Unchecked because that confinement is by construction, not by the type system:
/// every mutable field is touched only from the engine's own thread — the tap
/// callback and the display link both run there — and `install`/`setArmed` are the
/// only crossings, both serialised by the caller on the main actor.
private final class ScrollEngine: NSObject, @unchecked Sendable {

    /// Shortest distance a single detent may travel, before `speed`. Without a
    /// floor a slow turn of the wheel reports only a few pixels and the smoothing
    /// has nothing to work with, which reads as a sticky wheel.
    private static let stepFloor = 34.0
    /// Multiplies whatever the wheel reported. The input already carries the
    /// acceleration the driver applied, so scaling it keeps a slow turn short and
    /// a fast spin long instead of flattening both.
    private static let speed = 2.7
    /// Stage one: how fast the played-back position chases the target. Time
    /// constant, so a dropped frame costs distance rather than speed.
    private static let pullTau = 0.1
    /// Stage two: the same treatment applied to the per-frame *step*, which is
    /// what takes the jolt out of the first frame of a gesture. Two mild filters
    /// in series beat one aggressive one — the motion starts and ends softly
    /// without the long crawl a single long decay leaves behind.
    private static let smoothTau = 0.035
    /// Nothing below a pixel is worth an event; it is also the threshold that
    /// decides the gesture has arrived.
    private static let deadZone = 1.0
    /// Stamped on the events Kalfa posts so its own tap ignores them.
    private static let marker: Int64 = 0x4B_4C_50_41  // "KLPA"
    private static let fallbackInterval = 1.0 / 120.0

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var thread: Thread?

    private var isArmed = false
    private var displayLink: CADisplayLink?
    private var fallbackTimer: Timer?
    private var lastFrame: CFTimeInterval = 0

    /// Where the gesture is headed, where playback has got to, and the filtered
    /// step that is actually posted.
    private var target = (x: 0.0, y: 0.0)
    private var current = (x: 0.0, y: 0.0)
    private var output = (x: 0.0, y: 0.0)
    private var lastInput = (x: 0.0, y: 0.0)

    /// The wheel event that started the gesture, kept so every frame can be sent
    /// as that same event with new deltas — location, window and subtype included
    /// — rather than as a synthetic one the target app has to make sense of.
    private var template: CGEvent?
    private var targetPID: pid_t = 0

    // MARK: Control

    /// Installed once per launch. Tearing a tap down and creating another is what
    /// re-triggers the permission alert, so the switch arms it instead.
    func install(displayLink link: CADisplayLink?) -> Bool {
        if thread != nil { return tap != nil }

        displayLink = link
        let created = DispatchSemaphore(value: 0)

        let thread = Thread { [weak self] in
            guard let self else { created.signal(); return }
            let installed = installTap()
            if installed { installClock() }
            tapRunLoop = CFRunLoopGetCurrent()
            created.signal()
            guard installed else { return }
            // Returns only when the run loop is stopped.
            CFRunLoopRun()
        }
        thread.name = "com.aliakpoyraz.kalfa.scroll"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread

        // The tap has to exist before the caller can report itself running, and
        // creating it is the step that fails when permission was revoked.
        created.wait()
        guard tap != nil else {
            self.thread = nil
            Log.scroll.error("event tap could not be created")
            return false
        }
        return true
    }

    /// Arms or disarms the installed tap. A disarmed tap sees no events at all, so
    /// the wheel goes back to the system's own handling with no cost.
    func setArmed(_ armed: Bool) {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: armed)
        isArmed = armed
        if !armed { settle() }
    }

    /// Swaps in a link built against the current screen arrangement.
    func replaceDisplayLink(_ link: CADisplayLink?) {
        guard let link else { return }
        let old = displayLink
        displayLink = link
        perform(#selector(attach(_:)), on: thread ?? Thread.current, with: link, waitUntilDone: false)
        old?.invalidate()
    }

    @objc private func attach(_ link: CADisplayLink) {
        link.isPaused = true
        link.add(to: .current, forMode: .common)
    }

    private func installTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<ScrollEngine>.fromOpaque(userInfo).takeUnretainedValue()
            return engine.handle(type: type, event: event)
        }

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
        self.runLoopSource = source
        return true
    }

    /// Playback runs off the display's own vertical sync. A free-running timer
    /// lands two steps in one frame and none in the next — at 180 Hz against a
    /// 120 Hz timer that is every third frame, and it reads as stutter no matter
    /// how good the curve behind it is.
    private func installClock() {
        if let displayLink {
            attach(displayLink)
            return
        }
        // No screen to sync to (headless, or the link could not be made).
        let timer = Timer(timeInterval: Self.fallbackInterval, repeats: true) { [weak self] _ in
            self?.advance()
        }
        RunLoop.current.add(timer, forMode: .common)
        fallbackTimer = timer
        Log.scroll.notice("no display link; falling back to a timer")
    }

    // MARK: Tap callback

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system tears a tap down when it blocks; re-arming is the documented
        // recovery and is why a hitch does not permanently kill the wheel.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }
        guard type == .scrollWheel, isArmed else { return Unmanaged.passUnretained(event) }
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker { return Unmanaged.passUnretained(event) }
        if isTrackpad(event) { return Unmanaged.passUnretained(event) }

        // Command and control turn the wheel into zoom, for the app and for the
        // accessibility zoom respectively. Both read detents, not pixels.
        let modifiers = event.flags
        if modifiers.contains(.maskCommand) || modifiers.contains(.maskControl) {
            return Unmanaged.passUnretained(event)
        }

        var input = (
            x: travel(of: event, axis: 2),
            y: travel(of: event, axis: 1)
        )
        guard input.x != 0 || input.y != 0 else { return nil }

        // Shift means "scroll sideways". Apps apply that themselves to line
        // events, but not to the pixel events this posts, so it happens here.
        // Some mice do the swap in firmware; those arrive on the X axis already.
        if modifiers.contains(.maskShift), input.y != 0, input.x == 0 {
            input = (x: input.y, y: 0)
        }

        accumulate(input)
        template = event.copy()
        targetPID = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        resume()
        return nil
    }

    /// A trackpad announces itself through the gesture fields a wheel never fills:
    /// a scroll phase, a momentum phase, or the accumulated-gesture count. Reading
    /// those rather than the continuous flag also catches a Magic Mouse and any
    /// smoothing tool sitting ahead of Kalfa in the tap chain.
    private func isTrackpad(_ event: CGEvent) -> Bool {
        event.getDoubleValueField(.scrollWheelEventScrollPhase) != 0
            || event.getDoubleValueField(.scrollWheelEventMomentumPhase) != 0
            || event.getDoubleValueField(.scrollWheelEventScrollCount) != 0
            || event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
    }

    /// How far this detent should travel. macOS reports the same movement three
    /// ways and a given mouse fills only some of them: pixels first, then the
    /// fixed-point form, and lines last.
    private func travel(of event: CGEvent, axis: Int) -> Double {
        let points = event.getDoubleValueField(axis == 1 ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventPointDeltaAxis2)
        let fixed = event.getDoubleValueField(axis == 1 ? .scrollWheelEventFixedPtDeltaAxis1 : .scrollWheelEventFixedPtDeltaAxis2)
        let lines = Double(event.getIntegerValueField(axis == 1 ? .scrollWheelEventDeltaAxis1 : .scrollWheelEventDeltaAxis2))

        var value = points != 0 ? points : (fixed != 0 ? fixed : lines)
        guard value != 0 else { return 0 }
        if abs(value) < Self.stepFloor { value = value < 0 ? -Self.stepFloor : Self.stepFloor }
        return value * Self.speed
    }

    /// Adds to whatever is still in flight, so holding the wheel down builds speed
    /// instead of restarting the same short glide. A reversal is not an addition:
    /// the old distance is abandoned, otherwise flicking back up first has to pay
    /// off the downward travel still owed.
    private func accumulate(_ input: (x: Double, y: Double)) {
        if input.y * lastInput.y > 0 {
            target.y += input.y
        } else {
            target.y = input.y
            current.y = 0
        }
        if input.x * lastInput.x > 0 {
            target.x += input.x
        } else {
            target.x = input.x
            current.x = 0
        }
        lastInput = input
    }

    // MARK: Playback

    private func resume() {
        lastFrame = CACurrentMediaTime()
        displayLink?.isPaused = false
    }

    @objc func step(_ link: CADisplayLink) {
        advance()
    }

    private func advance() {
        let now = CACurrentMediaTime()
        // Real elapsed time rather than the nominal frame interval, so a dropped
        // frame moves the document by what it owes instead of falling behind.
        let dt = min(max(now - lastFrame, 0.001), 0.1)
        lastFrame = now

        let pull = 1 - exp(-dt / Self.pullTau)
        let smooth = 1 - exp(-dt / Self.smoothTau)

        let frame = (x: (target.x - current.x) * pull, y: (target.y - current.y) * pull)
        current = (x: current.x + frame.x, y: current.y + frame.y)
        output = (x: output.x + (frame.x - output.x) * smooth, y: output.y + (frame.y - output.y) * smooth)

        if max(abs(output.x), abs(output.y)) > Self.deadZone {
            post(output)
        }

        let residual = max(abs(target.x - current.x), abs(target.y - current.y))
        if residual <= Self.deadZone && max(abs(output.x), abs(output.y)) <= Self.deadZone {
            settle()
        }
    }

    private func settle() {
        target = (0, 0)
        current = (0, 0)
        output = (0, 0)
        lastInput = (0, 0)
        template = nil
        targetPID = 0
        displayLink?.isPaused = true
    }

    /// Sends the gesture's own event again with new deltas, straight to the
    /// process that owns it. Posting into the session tap instead would re-route
    /// every frame by where the pointer happens to be, so a glide that outlives
    /// the pointer leaving the window ends up scrolling the next window along.
    ///
    /// No scroll phase is set. Phases promise an app a trackpad gesture with its
    /// own momentum, and apps that believe it add a second layer of inertia on top
    /// of this one — the result reads as mush.
    private func post(_ delta: (x: Double, y: Double)) {
        guard let event = template?.copy() else { return }

        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: delta.y)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: delta.x)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: delta.y)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: delta.x)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64((delta.y / Self.stepFloor).rounded(.towardZero)))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64((delta.x / Self.stepFloor).rounded(.towardZero)))
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)

        if targetPID > 0 {
            event.postToPid(targetPID)
        } else {
            event.post(tap: .cgSessionEventTap)
        }
    }
}
