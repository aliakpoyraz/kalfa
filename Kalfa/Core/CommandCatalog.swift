import AppKit
import EzDPIKit
import SwiftUI
import KalfaUI

/// One runnable thing, named the way someone would search for it.
@MainActor
struct CommandItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let keywords: [String]
    let run: () -> Void
}

/// The actions Kalfa can run without a panel in front of it.
///
/// The menu bar panel and the floating palette read the same list: an ability
/// added here shows up in both, and neither view owns the wiring.
@MainActor
enum CommandCatalog {

    /// - Parameters:
    ///   - center: absent when no panel is up; the display and scene entries are
    ///     simply left out rather than faked.
    ///   - finish: what to say after an action runs.
    static func items(center: DisplayCenter?, finish: @escaping (String) -> Void) -> [CommandItem] {
        var items: [CommandItem] = []
        let audio = AudioService.shared
        let caffeine = CaffeineService.shared
        let presentation = PresentationMode.shared

        items.append(CommandItem(
            id: "mic",
            title: L10n.t("home.command.toggleMic"),
            detail: L10n.t("audio.mute.help"),
            icon: "mic.slash.fill",
            tint: .red,
            keywords: ["mikrofon", "mic", "mute", "sustur", "microphone"]
        ) {
            audio.setInputMuted(!audio.isInputMuted)
            finish(L10n.t(audio.isInputMuted ? "home.feedback.micOff" : "home.feedback.micOn"))
        })

        items.append(CommandItem(
            id: "awake",
            title: L10n.t("home.command.toggleAwake"),
            detail: L10n.t("caffeine.help"),
            icon: "cup.and.saucer.fill",
            tint: .orange,
            keywords: ["uyanık", "uyku", "awake", "sleep", "caffeine", "kafein"]
        ) {
            caffeine.toggle()
            finish(L10n.t(caffeine.isActive ? "home.feedback.awakeOn" : "home.feedback.awakeOff"))
        })

        items.append(CommandItem(
            id: "presentation",
            title: L10n.t("presentation"),
            detail: L10n.t("presentation.help"),
            icon: "rectangle.on.rectangle",
            tint: .indigo,
            keywords: ["sunum", "presentation", "toplantı", "meeting"]
        ) {
            presentation.toggle()
            finish(L10n.t(presentation.isOn ? "home.feedback.presentationOn" : "home.feedback.presentationOff"))
        })

        // Sound output. One entry per device, so "kulaklık" finds the headphones
        // rather than a menu the person then has to read.
        for device in audio.outputs where device.uid != audio.currentOutput?.uid {
            items.append(CommandItem(
                id: "output-\(device.uid)",
                title: L10n.t("home.command.output", device.name),
                detail: L10n.t("audio.output"),
                icon: "speaker.wave.2.fill",
                tint: .purple,
                keywords: [device.name, "ses", "çıkış", "output", "sound", "device", "cihaz"]
            ) {
                audio.select(device, direction: .output)
                finish(L10n.t("home.feedback.output", device.name))
            })
        }

        for (slot, key, icon) in windowSlots {
            items.append(CommandItem(
                id: "window-\(key)",
                title: L10n.t(key),
                detail: HotkeyService.shared.label(for: slot.hotkey),
                icon: icon,
                tint: .teal,
                keywords: ["pencere", "window", "yerleştir", "tile", "snap"]
            ) {
                let placed = WindowService.place(slot.slot)
                finish(L10n.t(placed ? "home.feedback.windowPlaced" : "home.feedback.windowFailed"))
            })
        }

        for mode in EzDPI.Mode.allCases {
            items.append(CommandItem(
                id: "dpi-\(mode.rawValue)",
                title: L10n.t("home.command.dpiMode", L10n.t("dpi.mode.\(mode.rawValue)")),
                detail: L10n.t("home.command.dpi.detail"),
                icon: "lock.shield",
                tint: .green,
                keywords: ["dpi", "proxy", "engel", "site", mode.rawValue]
            ) {
                EzDPI.mode = mode
                finish(L10n.t("home.feedback.dpiMode", L10n.t("dpi.mode.\(mode.rawValue)")))
            })
        }

        items.append(CommandItem(
            id: "health",
            title: L10n.t("health.title"),
            detail: L10n.t("health.subtitle"),
            icon: "stethoscope",
            tint: .orange,
            keywords: ["sağlık", "health", "izin", "permission", "durum", "status", "tanılama", "diagnostics"]
        ) {
            KalfaWindow.show(.health)
            finish(L10n.t("health.title"))
        })

        // The window's sections, so the palette reaches every page by name —
        // it is the only search surface now that the panel has none.
        for section in KalfaWindow.Section.allCases {
            items.append(CommandItem(
                id: "window-section-\(section.rawValue)",
                title: section.title,
                detail: L10n.t("window.subtitle.\(section.rawValue)"),
                icon: section.symbol,
                tint: section.role.tint,
                keywords: [section.rawValue, "pencere", "window", "aç", "open"]
            ) {
                KalfaWindow.show(section)
            })
        }

        items.append(CommandItem(
            id: "eject",
            title: L10n.t("disks.ejectAll"),
            detail: L10n.t("disks"),
            icon: "eject.fill",
            tint: .gray,
            keywords: ["disk", "eject", "çıkar", "usb", "harici"]
        ) {
            let failed = DiskService.ejectAll()
            finish(failed.isEmpty ? L10n.t("disks.ejected") : L10n.t("disks.busy", failed.joined(separator: ", ")))
        })

        guard let center else { return items }

        items.append(CommandItem(
            id: "refresh",
            title: L10n.t("header.rescan"),
            detail: L10n.t("home.command.refresh.detail"),
            icon: "arrow.clockwise",
            tint: .blue,
            keywords: ["yenile", "tara", "refresh", "rescan", "ekran"]
        ) {
            center.refreshNow()
            finish(L10n.t("home.feedback.refreshed"))
        })

        for profile in center.profiles.profiles {
            items.append(CommandItem(
                id: "scene-\(profile.id.uuidString)",
                title: L10n.t("home.command.scene", profile.name),
                detail: L10n.t("home.command.scene.detail"),
                icon: "sparkles.rectangle.stack",
                tint: .blue,
                keywords: [profile.name, "senaryo", "profil", "scene", "profile"]
            ) {
                Task {
                    let ok = await center.apply(profile)
                    finish(L10n.t(ok ? "home.feedback.sceneApplied" : "home.feedback.sceneFailed", profile.name))
                }
            })
        }

        return items
    }

    /// Diacritic- and case-insensitive so "cozunurluk" finds "çözünürlük".
    static func match(_ query: String, in items: [CommandItem]) -> [CommandItem] {
        let needle = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return items }
        return items.filter { item in
            ([item.title, item.detail] + item.keywords).contains { fold($0).contains(needle) }
        }
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private struct WindowSlot {
        let slot: WindowService.Slot
        let hotkey: HotkeyService.Action
    }

    private static var windowSlots: [(WindowSlot, String, String)] {
        [
            (WindowSlot(slot: .left, hotkey: .tileLeft), "windows.left", "rectangle.lefthalf.filled"),
            (WindowSlot(slot: .right, hotkey: .tileRight), "windows.right", "rectangle.righthalf.filled"),
            (WindowSlot(slot: .top, hotkey: .tileTop), "windows.top", "rectangle.tophalf.filled"),
            (WindowSlot(slot: .bottom, hotkey: .tileBottom), "windows.bottom", "rectangle.bottomhalf.filled"),
            (WindowSlot(slot: .center, hotkey: .tileCenter), "windows.center", "rectangle.center.inset.filled"),
            (WindowSlot(slot: .full, hotkey: .tileFull), "windows.full", "rectangle.fill"),
        ]
    }
}
