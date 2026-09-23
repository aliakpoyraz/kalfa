import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import IOKit.pwr_mgt
import Observation

/// Keeps the Mac awake for a while.
///
/// The assertion is what `caffeinate` uses, and it is released the moment the
/// process goes away — so a crash cannot leave a machine that never sleeps.
@MainActor
@Observable
final class CaffeineService {

    static let shared = CaffeineService()

    /// Minutes, or `nil` for "until I turn it off".
    enum Span: Int, CaseIterable, Identifiable {
        case indefinite = 0
        case fifteen = 15
        case thirty = 30
        case hour = 60

        var id: Int { rawValue }
        var minutes: Int? { self == .indefinite ? nil : rawValue }
    }

    private(set) var isActive = false
    private(set) var endsAt: Date?
    var span: Span = .indefinite

    /// Also keep the screen lit — and the screen saver away. Off by default:
    /// most of the time the point is an unattended job finishing, not a display
    /// burning.
    var keepsDisplayAwake: Bool {
        didSet {
            defaults.set(keepsDisplayAwake, forKey: Self.displayKey)
            // The kind of assertion is fixed when it is created.
            if isActive { restart() }
        }
    }

    /// Bundle identifiers that hold sleep off while they are running: a render,
    /// a download manager, a long build. The rule releases the machine the moment
    /// the last of them quits, which is the part people forget to do by hand.
    var watchedApps: [String] {
        didSet {
            defaults.set(watchedApps, forKey: Self.watchedKey)
            evaluateRule()
        }
    }

    /// True while the rule — rather than the user — is what is holding sleep off.
    private(set) var heldByRule = false

    /// Set when the user switches a rule-held session off by hand. Without it the
    /// next launch or quit of any app re-arms the rule a second later.
    private var ruleOverridden = false

    private var assertionID: IOPMAssertionID = 0
    private var expiryTask: Task<Void, Never>?
    private var activityID: IOPMAssertionID = 0
    private var activityTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private static let displayKey = "caffeineKeepsDisplayAwake"
    private static let watchedKey = "caffeineWatchedApps"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        keepsDisplayAwake = defaults.bool(forKey: Self.displayKey)
        watchedApps = defaults.stringArray(forKey: Self.watchedKey) ?? []
        observeApps()
        evaluateRule()
    }

    // MARK: App rule

    private func observeApps() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluateRule() }
            }
        }
    }

    private func evaluateRule() {
        guard !watchedApps.isEmpty else {
            ruleOverridden = false
            if heldByRule { heldByRule = false; stop() }
            return
        }

        let running = NSWorkspace.shared.runningApplications.contains { app in
            guard let id = app.bundleIdentifier else { return false }
            return watchedApps.contains(id)
        }

        if running {
            guard !ruleOverridden, !isActive else { return }
            span = .indefinite
            start()
            heldByRule = true
        } else {
            ruleOverridden = false
            if heldByRule {
                heldByRule = false
                stop()
            }
        }
    }

    /// Names for the panel; a bundle identifier is not something to show anyone.
    func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return url.deletingPathExtension().lastPathComponent
    }

    // MARK: Control

    func toggle() {
        guard isActive else {
            ruleOverridden = false
            start()
            return
        }
        if heldByRule {
            // The rule still matches; remember that the user overruled it.
            ruleOverridden = true
            heldByRule = false
        }
        stop()
    }

    /// `deadline` resumes an existing countdown; `nil` starts a fresh `span`.
    func start(until deadline: Date? = nil) {
        stop()

        let type = keepsDisplayAwake
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep

        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Kalfa" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            Log.display.error("caffeine assertion failed: \(result, privacy: .public)")
            return
        }

        assertionID = id
        isActive = true

        // A display assertion keeps the panel lit but does nothing about the
        // screen saver: that one runs off the HID idle timer, which no power
        // assertion touches. Measured on this machine — after
        // IOPMAssertionDeclareUserActivity the idle timer kept climbing.
        if keepsDisplayAwake { pulseUserActivity() }

        let target = deadline ?? span.minutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) }
        guard let target else {
            endsAt = nil
            return
        }
        endsAt = target
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, target.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    /// Nudges both idle timers every half minute — well inside the shortest
    /// screen saver setting, which is one minute.
    private func pulseUserActivity() {
        nudge()
        activityTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.nudge()
            }
        }
    }

    private func nudge() {
        declareUserActivity()
        resetInputIdleTimer()
    }

    /// Power management's own idle timer: pushes back display and system sleep.
    private func declareUserActivity() {
        var id = activityID
        let result = IOPMAssertionDeclareUserActivity("Kalfa" as CFString, kIOPMUserActiveLocal, &id)
        guard result == kIOReturnSuccess else {
            Log.display.error("caffeine user activity failed: \(result, privacy: .public)")
            return
        }
        activityID = id
    }

    /// The screen saver's timer. Only an input event resets it, so post a mouse
    /// move of zero distance: the pointer does not shift, the idle clock does.
    /// Needs Accessibility, which Kalfa already asks for; without it the display
    /// still stays lit, the saver just is not held back.
    private func resetInputIdleTimer() {
        guard AXIsProcessTrusted() else {
            Log.display.info("caffeine: no Accessibility, screen saver not held back")
            return
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let location = CGEvent(source: nil)?.location ?? .zero
        let move = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: location,
            mouseButton: .left
        )
        move?.post(tap: .cghidEventTap)
    }


    func stop() {
        expiryTask?.cancel()
        expiryTask = nil
        activityTask?.cancel()
        activityTask = nil
        endsAt = nil
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        if activityID != 0 {
            IOPMAssertionRelease(activityID)
            activityID = 0
        }
        isActive = false
    }

    /// The kind of assertion is fixed when it is created, so changing the
    /// display switch means a new one — with whatever countdown was left.
    private func restart() {
        let deadline = endsAt
        stop()
        start(until: deadline)
    }

    /// "23 dakika kaldı" for the panel.
    var remainingMinutes: Int? {
        guard let endsAt else { return nil }
        return max(0, Int(endsAt.timeIntervalSinceNow / 60).advanced(by: 1))
    }
}
