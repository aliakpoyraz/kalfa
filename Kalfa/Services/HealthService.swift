import AppKit
import CoreAudio
import EzDPIKit
import Foundation
import Observation
import KalfaUI

/// One screen that answers "why is that feature not working?".
///
/// Every check here maps to something Kalfa does that can fail silently: a
/// permission that was never granted, a monitor link that quietly dropped to
/// 4:2:2, a shortcut another app took. Each row carries the button that fixes it.
@MainActor
@Observable
final class HealthService {

    static let shared = HealthService()

    enum Level {
        case ok, warning, problem, info
    }

    struct Check: Identifiable {
        let id: String
        let title: String
        let detail: String
        let level: Level
        /// Button title and what it does, when there is something to press.
        var fixTitle: String?
        var fix: (() -> Void)?
    }

    private(set) var checks: [Check] = []
    private(set) var isRefreshing = false

    private init() {}

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var result: [Check] = []
        result.append(accessibilityCheck())
        result.append(audioCaptureCheck())
        result.append(contentsOf: hotkeyChecks())
        result.append(ddcCheck())
        result.append(contentsOf: linkChecks())
        result.append(dpiCheck())
        result.append(scrollCheck())
        result.append(installCheck())
        checks = result
    }

    // MARK: Checks

    private func accessibilityCheck() -> Check {
        let trusted = AXIsProcessTrusted()
        return Check(
            id: "accessibility",
            title: L10n.t("health.accessibility"),
            detail: L10n.t(trusted ? "health.accessibility.ok" : "health.accessibility.missing"),
            level: trusted ? .ok : .problem,
            fixTitle: trusted ? nil : L10n.t("health.open.settings"),
            fix: trusted ? nil : { Self.openSettings("Privacy_Accessibility") }
        )
    }

    /// Process taps are the only part of Kalfa that needs the audio recording
    /// permission, and macOS grants it per signature — an ad-hoc rebuild loses it.
    private func audioCaptureCheck() -> Check {
        guard #available(macOS 14.2, *) else {
            return Check(
                id: "audioCapture",
                title: L10n.t("health.audioCapture"),
                detail: L10n.t("mixer.unsupported"),
                level: .info
            )
        }

        switch AppAudioMixer.probeTapPermission() {
        case .granted:
            return Check(
                id: "audioCapture",
                title: L10n.t("health.audioCapture"),
                detail: L10n.t("health.audioCapture.ok"),
                level: .ok
            )
        case .denied(let status):
            return Check(
                id: "audioCapture",
                title: L10n.t("health.audioCapture"),
                detail: L10n.t("health.audioCapture.denied", String(status)),
                level: .problem,
                fixTitle: L10n.t("health.open.settings"),
                fix: { Self.openSettings("Privacy_Microphone") }
            )
        case .unknown:
            return Check(
                id: "audioCapture",
                title: L10n.t("health.audioCapture"),
                detail: L10n.t("health.audioCapture.unknown"),
                level: .info
            )
        }
    }

    private func hotkeyChecks() -> [Check] {
        let hotkeys = HotkeyService.shared
        let problems = hotkeys.problems
        guard !problems.isEmpty else {
            let count = HotkeyService.Action.allCases.filter { hotkeys.binding(for: $0) != nil }.count
            return [Check(
                id: "hotkeys",
                title: L10n.t("health.hotkeys"),
                detail: L10n.t("health.hotkeys.ok", count),
                level: .ok
            )]
        }

        return problems.keys.sorted { $0.rawValue < $1.rawValue }.map { action in
            let detail: String
            switch problems[action] {
            case .duplicate(let other):
                detail = L10n.t("hotkey.problem.duplicate", L10n.t(other.titleKey))
            default:
                detail = L10n.t("hotkey.problem.taken")
            }
            return Check(
                id: "hotkey-\(action.rawValue)",
                title: L10n.t(action.titleKey) + " · " + hotkeys.label(for: action),
                detail: detail,
                level: .warning
            )
        }
    }

    private func ddcCheck() -> Check {
        let screens = ScreenInfo.online().filter(\.supportsDDC)
        guard DDCService.shared.isSupported else {
            return Check(
                id: "ddc",
                title: L10n.t("health.ddc"),
                detail: L10n.t("health.ddc.unsupported"),
                level: .info
            )
        }
        return Check(
            id: "ddc",
            title: L10n.t("health.ddc"),
            detail: screens.isEmpty
                ? L10n.t("health.ddc.noExternal")
                : L10n.t("health.ddc.ok", screens.count),
            level: screens.isEmpty ? .info : .ok
        )
    }

    /// The finding that started this app: a link that renegotiates to 4:2:2 makes
    /// text look soft, and nothing in System Settings says so.
    private func linkChecks() -> [Check] {
        let screens = ScreenInfo.online()
        let setKey = DisplaySetKey(screens)
        return screens.compactMap { screen in
            guard let link = LinkInfo.link(for: screen.uuid, in: setKey) else { return nil }
            let isChromaSubsampled = link.label.contains("4:2:2") || link.label.contains("4:2:0")
            return Check(
                id: "link-\(screen.uuid)",
                title: screen.name,
                detail: link.label,
                level: isChromaSubsampled ? .warning : .ok
            )
        }
    }

    /// No "is the binary there?" question any more: the engine is compiled into
    /// the app, so the only thing worth reporting is whether it is running.
    private func dpiCheck() -> Check {
        Check(
            id: "dpi",
            title: L10n.t("health.dpi"),
            detail: EzDPI.isActive
                ? L10n.t("health.dpi.running")
                : L10n.t("health.dpi.idle", L10n.t("dpi.mode.\(EzDPI.mode.rawValue)")),
            level: .ok
        )
    }

    private func scrollCheck() -> Check {
        let scroll = ScrollService.isEnabledSetting
        let trusted = AXIsProcessTrusted()
        return Check(
            id: "scroll",
            title: L10n.t("health.scroll"),
            detail: scroll
                ? L10n.t(trusted ? "health.scroll.running" : "health.scroll.blocked")
                : L10n.t("health.scroll.off"),
            level: scroll && !trusted ? .problem : .ok
        )
    }

    /// Ad-hoc signatures are tied to the binary, so every rebuild from `dist`
    /// arrives as a stranger and the permissions have to be granted again.
    private func installCheck() -> Check {
        let path = Bundle.main.bundleURL.path
        let isInstalled = path.hasPrefix("/Applications/")
        return Check(
            id: "install",
            title: L10n.t("health.install"),
            detail: isInstalled ? path : L10n.t("health.install.elsewhere", path),
            level: isInstalled ? .ok : .info
        )
    }

    // MARK: Helpers

    static func openSettings(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
