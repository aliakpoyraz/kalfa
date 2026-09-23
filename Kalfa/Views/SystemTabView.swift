import AppKit
import SwiftUI
import KalfaUI

/// The switches that have nowhere else to live: staying awake, presenting,
/// timers, disks, DNS, window placement, and the `defaults` flags people keep in
/// a notes file.
///
/// Laid out as collapsed sections. Everything here is used occasionally rather
/// than daily, and a panel that opens two screens tall is a panel nobody reads.
struct SystemTabView: View {

    private let caffeine = CaffeineService.shared
    private let presentation = PresentationMode.shared
    private let timer = PowerTimer.shared
    private let network = NetworkTools.shared

    @State private var expanded: Section?
    @State private var ejectMessage: String?
    @State private var showsHiddenFiles = SystemTweaks.showsHiddenFiles
    @State private var showsAllExtensions = SystemTweaks.showsAllExtensions
    @State private var screenshotShadow = SystemTweaks.screenshotShadow
    @State private var dockIsInstant = SystemTweaks.dockIsInstant
    @State private var screenshotFormat = SystemTweaks.screenshotFormat
    @State private var screenshotFolder = SystemTweaks.screenshotFolder

    private enum Section: String {
        case awake, presentation, timer, disks, network, windows, shortcuts, tweaks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            section(.awake, L10n.t("caffeine"), caffeineValue) { stayAwake }
            section(.presentation, L10n.t("presentation"), presentation.isOn ? L10n.t("on") : nil) { presentationMode }
            section(.timer, L10n.t("timer"), timerValue) { powerTimer }
            section(.windows, L10n.t("windows"), nil) { windows }
            section(.network, L10n.t("dns"), network.dns.label) { dns }
            section(.disks, L10n.t("disks"), nil) { disks }
            section(.shortcuts, L10n.t("hotkeys"), nil) { HotkeysView() }
            section(.tweaks, L10n.t("tweaks"), nil) { tweaks }

        }
        .padding(14)
        .onAppear(perform: refreshTweakState)
    }

    // MARK: Section chrome

    @ViewBuilder
    private func section<Content: View>(
        _ id: Section,
        _ title: String,
        _ value: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                expanded = expanded == id ? nil : id
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded == id ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 8)
                    if let value {
                        Text(value)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded == id {
                content()
                    .padding(.leading, 16)
            }
        }
    }

    // MARK: Stay awake

    private var stayAwake: some View {
        VStack(alignment: .leading, spacing: 8) {
            SwitchRow(
                L10n.t("caffeine.now"),
                value: caffeineValue,
                isOn: Binding(get: { caffeine.isActive }, set: { _ in caffeine.toggle() }),
                help: L10n.t("caffeine.help")
            )

            Picker("", selection: Binding(get: { caffeine.span }, set: { caffeine.span = $0 })) {
                Text(L10n.t("caffeine.indefinite")).tag(CaffeineService.Span.indefinite)
                Text(L10n.t("caffeine.minutes", 15)).tag(CaffeineService.Span.fifteen)
                Text(L10n.t("caffeine.minutes", 30)).tag(CaffeineService.Span.thirty)
                Text(L10n.t("caffeine.minutes", 60)).tag(CaffeineService.Span.hour)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(caffeine.isActive)

            Toggle(L10n.t("caffeine.display"), isOn: Binding(
                get: { caffeine.keepsDisplayAwake },
                set: { caffeine.keepsDisplayAwake = $0 }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)

            Divider()

            Text(L10n.t("caffeine.rule"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(caffeine.watchedApps, id: \.self) { bundleID in
                HStack(spacing: 6) {
                    Text(caffeine.appName(bundleID))
                        .font(.caption)
                    Spacer(minLength: 8)
                    Button {
                        caffeine.watchedApps.removeAll { $0 == bundleID }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Button(L10n.t("caffeine.rule.add")) { pickApp() }
                .buttonStyle(.borderless)
                .font(.caption)

            Text(L10n.t("caffeine.rule.help"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier,
              !caffeine.watchedApps.contains(bundleID)
        else { return }
        caffeine.watchedApps.append(bundleID)
    }

    private var caffeineValue: String? {
        guard caffeine.isActive else { return nil }
        if caffeine.heldByRule { return L10n.t("caffeine.byRule") }
        guard let minutes = caffeine.remainingMinutes else { return L10n.t("caffeine.untilOff") }
        return L10n.t("caffeine.remaining", minutes)
    }

    // MARK: Presentation

    private var presentationMode: some View {
        VStack(alignment: .leading, spacing: 8) {
            SwitchRow(
                L10n.t("presentation.on"),
                isOn: Binding(get: { presentation.isOn }, set: { _ in presentation.toggle() }),
                help: L10n.t("presentation.help")
            )
            Toggle(L10n.t("presentation.blackout"), isOn: Binding(
                get: { presentation.blacksOutOtherScreens },
                set: { presentation.blacksOutOtherScreens = $0 }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
            Text(L10n.t("presentation.help"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Timer

    private var powerTimer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: Binding(get: { timer.ending }, set: { timer.ending = $0 })) {
                ForEach(PowerTimer.Ending.allCases) { ending in
                    Text(ending.label).tag(ending)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(timer.isArmed)

            Stepper(
                L10n.t("timer.minutes", timer.minutes),
                value: Binding(get: { timer.minutes }, set: { timer.minutes = $0 }),
                in: 5...240,
                step: 5
            )
            .font(.caption)
            .disabled(timer.isArmed)

            HStack {
                if timer.isArmed {
                    Button(L10n.t("timer.cancel")) { timer.cancel() }
                } else {
                    Button(L10n.t("timer.arm")) { timer.arm() }
                }
                Spacer()
            }
            .font(.caption)
        }
    }

    private var timerValue: String? {
        guard let minutes = timer.remainingMinutes else { return nil }
        return L10n.t("timer.remaining", minutes, timer.ending.label)
    }

    // MARK: Windows

    private var windows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(windowRows, id: \.0) { label, action, slot in
                HStack(spacing: 8) {
                    Button(label) { WindowService.place(slot) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    Spacer(minLength: 8)
                    Text(action)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            Text(L10n.t("windows.help"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var windowRows: [(String, String, WindowService.Slot)] {
        [
            (L10n.t("windows.left"), HotkeyService.shared.label(for: .tileLeft), .left),
            (L10n.t("windows.right"), HotkeyService.shared.label(for: .tileRight), .right),
            (L10n.t("windows.top"), HotkeyService.shared.label(for: .tileTop), .top),
            (L10n.t("windows.bottom"), HotkeyService.shared.label(for: .tileBottom), .bottom),
            (L10n.t("windows.center"), HotkeyService.shared.label(for: .tileCenter), .center),
            (L10n.t("windows.full"), HotkeyService.shared.label(for: .tileFull), .full),
        ]
    }

    // MARK: DNS

    private var dns: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: Binding(get: { network.dns }, set: { network.setDNS($0) })) {
                ForEach(NetworkTools.DNSChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(network.dnsDetail)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(L10n.t("dns.help"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Disks

    private var disks: some View {
        VStack(alignment: .leading, spacing: 6) {
            let volumes = DiskService.ejectable()
            if volumes.isEmpty {
                Text(L10n.t("disks.none"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(volumes) { volume in
                    Text(volume.name)
                        .font(.caption)
                }
                Button(L10n.t("disks.ejectAll")) {
                    let failed = DiskService.ejectAll()
                    ejectMessage = failed.isEmpty
                        ? L10n.t("disks.ejected")
                        : L10n.t("disks.busy", failed.joined(separator: ", "))
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            if let ejectMessage {
                Text(ejectMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: defaults flags

    private var tweaks: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            Toggle(L10n.t("tweaks.instantDock"), isOn: Binding(
                get: { dockIsInstant },
                set: {
                    dockIsInstant = $0
                    SystemTweaks.dockIsInstant = $0
                }
            ))

            HStack(spacing: 8) {
                Text(L10n.t("tweaks.screenshotFormat"))
                    .font(.caption)
                Spacer(minLength: 8)
                Menu(screenshotFormat.uppercased()) {
                    ForEach(["png", "jpg", "heic", "pdf", "tiff"], id: \.self) { format in
                        Button(format.uppercased()) {
                            screenshotFormat = format
                            SystemTweaks.screenshotFormat = format
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(spacing: 8) {
                Text(L10n.t("tweaks.screenshotFolder"))
                    .font(.caption)
                Spacer(minLength: 8)
                Button(screenshotFolder.lastPathComponent) { pickScreenshotFolder() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }

            Text(L10n.t("tweaks.help"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(.checkbox)
        .font(.caption)
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
