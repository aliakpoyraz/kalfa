import AppKit
import CoreGraphics
import EzDPIKit
import Foundation
import Observation
import KalfaUI

/// The single source of truth about what is plugged in right now.
///
/// It listens to window server reconfiguration events, rebuilds its snapshot, and
/// re-applies a saved profile when the new arrangement has one. The debounce is
/// not cosmetic: unplugging a display emits a burst of callbacks (begin, mode
/// change, desktop moved, end) and reading modes mid-burst returns garbage.
@MainActor
@Observable
final class DisplayCenter {

    // MARK: Observable state

    private(set) var screens: [ScreenInfo] = []
    private(set) var modesByUUID: [String: [ScreenMode]] = [:]
    private(set) var currentModeByUUID: [String: ScreenMode] = [:]
    /// Set while a reconfiguration is in flight, so the UI can disable controls.
    private(set) var isApplying = false
    /// Non-nil while an unproven mode is on screen awaiting confirmation.
    private(set) var pendingRevert: PendingRevert?
    /// Last thing that happened, shown at the bottom of the menu.
    private(set) var statusMessage: String?

    var settings = AppSettings()
    let profiles: ProfileStore

    /// Identifies the current arrangement — the key macOS itself keys settings on.
    var setKey: DisplaySetKey { DisplaySetKey(screens) }

    /// The lid is shut: an external display is driving the desktop and the
    /// built-in panel has dropped off the online list entirely.
    var isClamshell: Bool {
        !screens.isEmpty && !screens.contains(where: \.isBuiltIn)
    }

    // MARK: Internals

    /// A mode macOS does not vouch for is applied on approval: if the picture is
    /// unreadable the countdown puts the old one back without the user having to
    /// see anything to click it.
    struct PendingRevert: Identifiable {
        let id = UUID()
        let screenUUID: String
        let screenName: String
        let previous: ScreenMode
        let applied: ScreenMode
        var secondsLeft: Int
    }

    private var refreshTask: Task<Void, Never>?
    private var revertTask: Task<Void, Never>?
    /// Reconfigurations we caused ourselves must not retrigger auto-apply.
    private var suppressAutoApplyUntil = Date.distantPast
    private var callbackRegistered = false

    /// The one instance. The panel, the window and the palette all drive the
    /// same display state, and the window is built by AppKit — there is no
    /// SwiftUI environment to hand it down through.
    @MainActor static let shared = DisplayCenter()

    init(profiles: ProfileStore = ProfileStore()) {
        self.profiles = profiles
        refreshNow()
        registerForReconfiguration()
    }

    deinit {
        // Deliberately not unregistering: the app lives for the whole login
        // session, and the callback holds an unretained pointer that only the
        // shared instance ever uses.
    }

    // MARK: Snapshot

    /// Rebuilds the snapshot immediately. Cheap enough to call from the UI.
    func refreshNow() {
        let online = ScreenInfo.online()
        screens = online

        var modes: [String: [ScreenMode]] = [:]
        var current: [String: ScreenMode] = [:]
        for screen in online {
            modes[screen.uuid] = ModeService.modes(for: screen.displayID)
            current[screen.uuid] = ModeService.current(for: screen.displayID)
        }
        modesByUUID = modes
        currentModeByUUID = current
    }

    func modes(for screen: ScreenInfo) -> [ScreenMode] {
        modesByUUID[screen.uuid] ?? []
    }

    func currentMode(for screen: ScreenInfo) -> ScreenMode? {
        currentModeByUUID[screen.uuid]
    }

    // MARK: Derived queries
    //
    // These read the cached mode list rather than re-enumerating. SwiftUI
    // evaluates a view body far more often than displays change, and enumerating
    // SkyLight's 300-odd modes on every pass is not free.

    func scaleSibling(for screen: ScreenInfo, hiDPI: Bool) -> ScreenMode? {
        guard let current = currentMode(for: screen) else { return nil }
        return ModeService.scaleSibling(of: current, hiDPI: hiDPI, among: modes(for: screen))
    }

    func refreshSibling(for screen: ScreenInfo, fastest: Bool) -> ScreenMode? {
        guard let current = currentMode(for: screen) else { return nil }
        return ModeService.refreshSibling(of: current, fastest: fastest, among: modes(for: screen))
    }

    func peakRefreshRate(for screen: ScreenInfo) -> Double? {
        guard let current = currentMode(for: screen) else { return nil }
        return ModeService.peakRefreshRate(for: current, among: modes(for: screen))
    }

    func panelPixelSize(for screen: ScreenInfo) -> (width: Int, height: Int)? {
        ModeService.panelPixelSize(among: modes(for: screen))
    }

    /// How a mode's backing store lands on this panel's pixel grid.
    func rendering(of mode: ScreenMode, on screen: ScreenInfo) -> ModeService.Rendering? {
        guard let panel = panelPixelSize(for: screen) else { return nil }
        return ModeService.rendering(of: mode, panel: panel)
    }

    /// The best-looking mode at this display's native pixel grid: a 2× backing
    /// store over the panel's own resolution when one exists, otherwise 1:1.
    func sharpestMode(for screen: ScreenInfo) -> ScreenMode? {
        guard let panel = panelPixelSize(for: screen) else { return nil }
        let candidates = modes(for: screen).filter {
            !ModeService.rendering(of: $0, panel: panel).isSoft
        }
        // Prefer HiDPI (proper Retina metrics), then the highest refresh rate.
        return candidates.max { a, b in
            if a.isHiDPI != b.isHiDPI { return !a.isHiDPI }
            return a.refreshRate < b.refreshRate
        }
    }

    // MARK: Applying modes

    func apply(_ mode: ScreenMode, to screen: ScreenInfo) async {
        isApplying = true
        defer { isApplying = false }

        cancelPendingRevert()
        let previous = currentMode(for: screen)

        suppressAutoApply(for: 6)
        let ok = await ModeService.apply(
            mode,
            to: screen.displayID,
            persistence: settings.persistModeChanges ? .permanent : .session
        )
        DDCService.shared.invalidate()
        refreshNow()

        guard ok else {
            status(L10n.t("status.applyFailed", screen.name))
            return
        }
        status(L10n.t("status.applied", screen.name, mode.summary))

        // Modes CoreGraphics withheld carry no safety guarantee from macOS. Arm
        // the countdown so a black or scrambled picture undoes itself.
        if needsConfirmation(mode), let previous, previous.id != mode.id {
            armRevert(screen: screen, previous: previous, applied: mode)
        }
    }

    private func needsConfirmation(_ mode: ScreenMode) -> Bool {
        mode.isExtended || !mode.isSafe
    }

    // MARK: Confirm or revert

    /// Keeps the new mode and disarms the countdown.
    func confirmPendingMode() {
        let pending = pendingRevert
        cancelPendingRevert()
        if let pending {
            status(L10n.t("status.kept", pending.screenName, pending.applied.summary))
        }
    }

    /// Puts the previous mode back immediately.
    func revertPendingMode() async {
        guard let pending = pendingRevert else { return }
        cancelPendingRevert()
        await performRevert(pending)
    }

    /// The actual restore. Kept separate from `revertPendingMode` so the
    /// countdown can call it without cancelling the task it is itself running on.
    private func performRevert(_ pending: PendingRevert) async {
        guard let displayID = ScreenInfo.displayID(forUUID: pending.screenUUID) else {
            status(L10n.t("status.displayGone", pending.screenName))
            return
        }

        isApplying = true
        defer { isApplying = false }

        suppressAutoApply(for: 6)
        let ok = await ModeService.apply(
            pending.previous,
            to: displayID,
            persistence: settings.persistModeChanges ? .permanent : .session
        )
        DDCService.shared.invalidate()
        refreshNow()
        status(ok
               ? L10n.t("status.reverted", pending.screenName)
               : L10n.t("status.revertFailed", pending.screenName))
    }

    private func armRevert(screen: ScreenInfo, previous: ScreenMode, applied: ScreenMode) {
        let pending = PendingRevert(
            screenUUID: screen.uuid,
            screenName: screen.name,
            previous: previous,
            applied: applied,
            secondsLeft: 15
        )
        pendingRevert = pending

        revertTask = Task { @MainActor [weak self] in
            for remaining in stride(from: pending.secondsLeft - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                // A different countdown replaced this one, or the user answered.
                guard self.pendingRevert?.id == pending.id else { return }
                self.pendingRevert?.secondsLeft = remaining
            }
            guard !Task.isCancelled, let self, self.pendingRevert?.id == pending.id else { return }
            self.pendingRevert = nil
            self.revertTask = nil
            await self.performRevert(pending)
        }
    }

    private func cancelPendingRevert() {
        revertTask?.cancel()
        revertTask = nil
        pendingRevert = nil
    }

    // MARK: Profiles

    /// Captures the current arrangement, optionally including DDC values and the
    /// rest of the machine's state — sound, DPI, staying awake.
    func captureProfile(
        named name: String,
        includeBrightness: Bool,
        includeAudio: Bool = false,
        includeDPI: Bool = false,
        includeCaffeine: Bool = false
    ) async -> Profile {
        var entries: [Profile.Entry] = []

        for screen in screens {
            guard let mode = currentMode(for: screen) else { continue }
            var entry = Profile.Entry(
                displayUUID: screen.uuid,
                displayName: screen.name,
                mode: mode.fingerprint
            )
            if includeBrightness, screen.supportsDDC {
                entry.brightness = await DDCService.shared
                    .read(.brightness, from: screen.displayID)?.percent
                entry.contrast = await DDCService.shared
                    .read(.contrast, from: screen.displayID)?.percent
            }
            entries.append(entry)
        }

        let audio = includeAudio ? AudioService.shared.currentOutput : nil
        let profile = Profile(
            name: name,
            setKey: setKey,
            entries: entries,
            restoresBrightness: includeBrightness,
            audioOutputUID: audio?.uid,
            audioOutputName: audio?.name,
            dpiMode: includeDPI ? EzDPI.mode.rawValue : nil,
            caffeine: includeCaffeine ? CaffeineService.shared.isActive : nil
        )
        profiles.add(profile)
        status(L10n.t("status.profileSaved", name))
        return profile
    }

    /// The non-display half of a scene. Each part is skipped unless the scene
    /// actually carries it, so applying an old display-only profile leaves the
    /// sound and the DPI switch exactly where they were.
    private func applyExtras(of profile: Profile) {
        if let uid = profile.audioOutputUID {
            // A scene saved with headphones plugged in is applied often enough
            // with them unplugged; that is a no-op, not an error.
            AudioService.shared.selectDevice(uid: uid)
        }
        if let raw = profile.dpiMode, let mode = EzDPI.Mode(rawValue: raw) {
            EzDPI.mode = mode
        }
        if let caffeine = profile.caffeine {
            caffeine ? CaffeineService.shared.start() : CaffeineService.shared.stop()
        }
    }

    /// Default name for a new profile, based on what is connected.
    func suggestedProfileName() -> String {
        if isClamshell { return L10n.t("save.defaultName.clamshell") }
        if screens.count == 1 { return screens.first?.name ?? L10n.t("header.displayCount.one") }
        return L10n.t("save.defaultName.count", screens.count)
    }

    @discardableResult
    func apply(_ profile: Profile) async -> Bool {
        isApplying = true
        defer { isApplying = false }

        suppressAutoApply(for: 8)

        var requests: [ModeService.Request] = []
        var missing: [String] = []

        for entry in profile.entries {
            guard let displayID = ScreenInfo.displayID(forUUID: entry.displayUUID) else {
                missing.append(entry.displayName)
                continue
            }
            guard let mode = ModeService.match(entry.mode, on: displayID) else {
                missing.append(entry.displayName)
                continue
            }
            requests.append(ModeService.Request(displayID: displayID, mode: mode))
        }

        let ok = await ModeService.apply(
            requests,
            persistence: settings.persistModeChanges ? .permanent : .session
        )

        DDCService.shared.invalidate()

        applyExtras(of: profile)

        if ok, profile.restoresBrightness {
            for entry in profile.entries {
                guard let displayID = ScreenInfo.displayID(forUUID: entry.displayUUID) else { continue }
                if let brightness = entry.brightness {
                    await DDCService.shared.write(.brightness, percent: brightness, to: displayID)
                }
                if let contrast = entry.contrast {
                    await DDCService.shared.write(.contrast, percent: contrast, to: displayID)
                }
            }
        }

        refreshNow()

        if !missing.isEmpty {
            status(L10n.t(
                "status.profileMissingModes", profile.name, missing.joined(separator: ", ")
            ))
        } else {
            status(ok
                   ? L10n.t("status.profileApplied", profile.name)
                   : L10n.t("status.profileFailed", profile.name))
        }
        return ok && missing.isEmpty
    }

    // MARK: Reconfiguration handling

    private func registerForReconfiguration() {
        guard !callbackRegistered else { return }
        callbackRegistered = true

        let context = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            guard let userInfo else { return }
            // Only the settled half of the event pair carries a usable state.
            guard flags.contains(.setModeFlag)
                    || flags.contains(.addFlag)
                    || flags.contains(.removeFlag)
                    || flags.contains(.enabledFlag)
                    || flags.contains(.disabledFlag)
                    || flags.contains(.desktopShapeChangedFlag)
            else { return }

            let center = Unmanaged<DisplayCenter>.fromOpaque(userInfo).takeUnretainedValue()
            Task { @MainActor in center.displaysDidChange() }
        }, context)
    }

    private func displaysDidChange() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            // Ride out the callback burst before reading anything.
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled, let self else { return }

            DDCService.shared.invalidate()
            self.refreshNow()
            await self.autoApplyIfNeeded()
        }
    }

    private func autoApplyIfNeeded() async {
        guard settings.autoApplyProfiles else { return }
        guard Date() >= suppressAutoApplyUntil else {
            Log.profile.debug("auto-apply suppressed: change was self-inflicted")
            return
        }
        guard !screens.isEmpty else { return }
        guard let profile = profiles.autoApplyProfile(for: setKey) else { return }

        // Already in the wanted state — applying would flash the desktop for nothing.
        guard !matchesCurrentState(profile) else {
            Log.profile.debug("auto-apply skipped: already matching")
            return
        }

        Log.profile.info("auto-applying profile \(profile.name, privacy: .public)")
        await apply(profile)
    }

    private func matchesCurrentState(_ profile: Profile) -> Bool {
        for entry in profile.entries {
            guard let screen = screens.first(where: { $0.uuid == entry.displayUUID }),
                  let mode = currentMode(for: screen),
                  mode.fingerprint == entry.mode
            else { return false }
        }
        return true
    }

    private func suppressAutoApply(for seconds: TimeInterval) {
        suppressAutoApplyUntil = Date().addingTimeInterval(seconds)
    }

    // MARK: Status line

    private func status(_ message: String) {
        statusMessage = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            if self?.statusMessage == message { self?.statusMessage = nil }
        }
    }
}
