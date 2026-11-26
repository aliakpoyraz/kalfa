import AppKit
import SwiftUI
import KalfaUI

/// How the desktop behaves: where windows go, where the Dock lives, how the
/// wheel scrolls, and the `defaults` flags people keep in a notes file.
struct DesktopPage: View {

    private let dockLock = DockLockService.shared

    @State private var ejectMessage: String?
    @State private var showsHiddenFiles = SystemTweaks.showsHiddenFiles
    @State private var showsAllExtensions = SystemTweaks.showsAllExtensions
    @State private var screenshotShadow = SystemTweaks.screenshotShadow
    @State private var dockIsInstant = SystemTweaks.dockIsInstant
    @State private var screenshotFormat = SystemTweaks.screenshotFormat
    @State private var screenshotFolder = SystemTweaks.screenshotFolder

    var body: some View {
        Form {
            Section {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: KalfaDesign.s), count: 3),
                    spacing: KalfaDesign.s
                ) {
                    ForEach(windowSlots, id: \.title) { slot in
                        Button {
                            WindowService.place(slot.slot)
                        } label: {
                            VStack(spacing: KalfaDesign.xs) {
                                Image(systemName: slot.symbol)
                                    .font(KalfaDesign.titleFont)
                                    .foregroundStyle(.secondary)
                                Text(slot.title)
                                    .font(KalfaDesign.bodyFont)
                                    .lineLimit(1)
                                Text(HotkeyService.shared.label(for: slot.hotkey))
                                    .font(KalfaDesign.captionFont.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, KalfaDesign.xs)
                        }
                    }
                }
            } header: {
                Text(L10n.t("windows"))
            } footer: {
                Text(L10n.t("windows.help")).kalfaFootnote()
            }

            Section {
                Picker(L10n.t("tweaks.dockLock"), selection: Binding(
                    get: { dockLock.mode },
                    set: { dockLock.mode = $0 }
                )) {
                    ForEach(DockLockService.Mode.allCases, id: \.self) { mode in
                        Text(L10n.t("dock.mode.\(mode.rawValue)")).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                if dockLock.isEnabled && !dockLock.isTrusted {
                    LabeledContent {
                        Button(L10n.t("scroll.permission.grant")) { dockLock.requestPermission() }
                    } label: {
                        Label(L10n.t("home.state.needsPermission"), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(KalfaTone.warn.color)
                    }
                }
                Toggle(L10n.t("tweaks.instantDock"), isOn: Binding(
                    get: { dockIsInstant },
                    set: {
                        dockIsInstant = $0
                        SystemTweaks.dockIsInstant = $0
                    }
                ))
            } header: {
                Text("Dock")
            } footer: {
                Text(L10n.t("tweaks.dockLock.help")).kalfaFootnote()
            }

            Section(L10n.t("scroll")) {
                ScrollSettingsView()
            }

            Section {
                Toggle(L10n.t("tweaks.hiddenFiles"), isOn: Binding(
                    get: { showsHiddenFiles },
                    set: {
                        showsHiddenFiles = $0
                        SystemTweaks.showsHiddenFiles = $0
                    }
                ))
                Toggle(L10n.t("tweaks.extensions"), isOn: Binding(
                    get: { showsAllExtensions },
                    set: {
                        showsAllExtensions = $0
                        SystemTweaks.showsAllExtensions = $0
                    }
                ))
                Toggle(L10n.t("tweaks.screenshotShadow"), isOn: Binding(
                    get: { screenshotShadow },
                    set: {
                        screenshotShadow = $0
                        SystemTweaks.screenshotShadow = $0
                    }
                ))
                Picker(L10n.t("tweaks.screenshotFormat"), selection: Binding(
                    get: { screenshotFormat },
                    set: {
                        screenshotFormat = $0
                        SystemTweaks.screenshotFormat = $0
                    }
                )) {
                    ForEach(["png", "jpg", "heic", "pdf", "tiff"], id: \.self) { format in
                        Text(format.uppercased()).tag(format)
                    }
                }
                LabeledContent(L10n.t("tweaks.screenshotFolder")) {
                    Button(screenshotFolder.lastPathComponent) { pickScreenshotFolder() }
                }
            } header: {
                Text(L10n.t("tweaks"))
            } footer: {
                Text(L10n.t("tweaks.help")).kalfaFootnote()
            }

            Section(L10n.t("disks")) {
                let volumes = DiskService.ejectable()
                if volumes.isEmpty {
                    Text(L10n.t("disks.none")).foregroundStyle(.secondary)
                } else {
                    ForEach(volumes) { volume in
                        Label(volume.name, systemImage: "externaldrive")
                    }
                    Button(L10n.t("disks.ejectAll")) {
                        let failed = DiskService.ejectAll()
                        ejectMessage = failed.isEmpty
                            ? L10n.t("disks.ejected")
                            : L10n.t("disks.busy", failed.joined(separator: ", "))
                    }
                }
                if let ejectMessage {
                    Text(ejectMessage).kalfaFootnote()
                }
            }
        }
        .kalfaForm()
        .onAppear(perform: refreshTweakState)
    }

    private struct WindowSlot {
        let title: String
        let symbol: String
        let slot: WindowService.Slot
        let hotkey: HotkeyService.Action
    }

    private var windowSlots: [WindowSlot] {
        [
            WindowSlot(title: L10n.t("windows.left"), symbol: "rectangle.lefthalf.filled", slot: .left, hotkey: .tileLeft),
            WindowSlot(title: L10n.t("windows.right"), symbol: "rectangle.righthalf.filled", slot: .right, hotkey: .tileRight),
            WindowSlot(title: L10n.t("windows.full"), symbol: "rectangle.fill", slot: .full, hotkey: .tileFull),
            WindowSlot(title: L10n.t("windows.top"), symbol: "rectangle.tophalf.filled", slot: .top, hotkey: .tileTop),
            WindowSlot(title: L10n.t("windows.bottom"), symbol: "rectangle.bottomhalf.filled", slot: .bottom, hotkey: .tileBottom),
            WindowSlot(title: L10n.t("windows.center"), symbol: "rectangle.center.inset.filled", slot: .center, hotkey: .tileCenter),
        ]
    }

    private func pickScreenshotFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        screenshotFolder = url
        SystemTweaks.setScreenshotFolder(url)
    }

    private func refreshTweakState() {
        showsHiddenFiles = SystemTweaks.showsHiddenFiles
        showsAllExtensions = SystemTweaks.showsAllExtensions
        screenshotShadow = SystemTweaks.screenshotShadow
        dockIsInstant = SystemTweaks.dockIsInstant
        screenshotFormat = SystemTweaks.screenshotFormat
        screenshotFolder = SystemTweaks.screenshotFolder
    }
}
