import EzDPIKit
import SwiftUI
import UpkeepKit
import KalfaUI

/// The menu bar panel: a remote for the Mac.
///
/// Reading down: the two sliders reached for most, the six switches flicked on
/// the way past, then three subjects worth a look without sitting down. The
/// panel keeps one height — a subject opens in place and goes back, rather than
/// unfolding and pushing everything under it off the screen. Anything that is
/// set once and left alone is in the window.
struct RootView: View {

    private enum Route {
        case home, display, monitor
    }

    @Environment(DisplayCenter.self) private var center
    @Environment(ScrollService.self) private var scroll

    @State private var route: Route = .home
    @State private var selectedUUID: String?
    @State private var feedback: String?
    @State private var showingSaveSheet = false

    private let audio = AudioService.shared
    private let caffeine = CaffeineService.shared
    private let presentation = PresentationMode.shared
    private let dockLock = DockLockService.shared
    private let brightness = BrightnessService.shared
    private let health = HealthService.shared
    /// Observed, not just held: the DPI engine starting or stopping has to
    /// redraw its switch.
    @StateObject private var dpi = EzDPIStatus()
    @ObservedObject private var monitor = Upkeep.monitor

    var body: some View {
        Group {
            switch route {
            case .home: home
            case .display: displayPage
            case .monitor: monitorPage
            }
        }
        .padding(KalfaDesign.m)
        .frame(width: KalfaDesign.panelWidth)
        // Thick, not ultra thin: this is a menu surface that has to stay
        // legible over whatever happens to be on screen behind it.
        .background(.thickMaterial)
        // Rebuilds the panel when the language changes; SwiftUI cannot see into
        // the strings bundle on its own.
        .id(center.settings.language.rawValue)
        .animation(KalfaDesign.motion, value: feedback)
        .onAppear {
            CommandPalette.shared.center = center
            // The backlight may have been moved with the keyboard since the
            // panel was last open.
            center.syncBrightness()
            health.refresh()
            // Sampled only while the panel is up, so the summary line is live
            // without a meter running in the background all day.
            monitor.retain()
        }
        .onDisappear {
            monitor.release()
            route = .home
        }
        .sheet(isPresented: $showingSaveSheet) {
            SaveProfileView()
                .environment(center)
        }
    }

    private var screen: ScreenInfo? {
        center.screens.first { $0.uuid == selectedUUID } ?? center.screens.first
    }

    // MARK: Home

    private var home: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.m) {
            if let pending = center.pendingRevert {
                revertBanner(pending)
            }
            if center.screens.count > 1 {
                screenPicker
            }
            if let screen {
                VStack(alignment: .leading, spacing: KalfaDesign.xs) {
                    BrightnessSlider(screen: screen)
                    BrightnessNote(screen: screen)
                        .padding(.leading, 26)
                }
            }
            volume
            toggles
            subjects

            if let feedback {
                Label(feedback, systemImage: "checkmark.circle.fill")
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            footer
        }
    }

    /// Only shown with more than one display: which of them the brightness
    /// slider and the display page are about.
    private var screenPicker: some View {
        Picker("", selection: Binding(
            get: { screen?.uuid ?? "" },
            set: { selectedUUID = $0 }
        )) {
            ForEach(center.screens) { item in
                Text(item.isBuiltIn ? L10n.t("display.builtIn.short") : item.name).tag(item.uuid)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var volume: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.xs) {
            KalfaSlider(
                value: Binding(get: { audio.volume * 100 }, set: { audio.volume = $0 / 100 }),
                in: 0...100,
                symbol: audio.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                label: L10n.t("tab.audio"),
                valueText: "\(Int((audio.volume * 100).rounded()))",
                isEnabled: audio.currentOutput != nil
            )

            Menu {
                ForEach(audio.outputs) { device in
                    Button {
                        audio.select(device, direction: .output)
                        say(L10n.t("home.feedback.output", device.name))
                    } label: {
                        if device.id == audio.currentOutput?.id {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            } label: {
                Text(audio.currentOutput?.name ?? L10n.t("audio.none.short"))
                    .font(KalfaDesign.captionFont)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(audio.outputs.isEmpty)
            .padding(.leading, 26)
        }
    }

    // MARK: Toggles

    private var toggles: some View {
        HStack(alignment: .top, spacing: KalfaDesign.xs) {
            KalfaQuickToggle(
                L10n.t("quick.mic"),
                symbol: audio.isInputMuted ? "mic.slash.fill" : "mic.fill",
                isOn: audio.isInputMuted,
                tone: .bad,
                help: "\(L10n.t(audio.isInputMuted ? "home.state.muted" : "home.state.ready")) · \(HotkeyService.shared.label(for: .muteInput))"
            ) {
                audio.setInputMuted(!audio.isInputMuted)
                say(L10n.t(audio.isInputMuted ? "home.feedback.micOff" : "home.feedback.micOn"))
            }

            KalfaQuickToggle(
                L10n.t("quick.awake"),
                symbol: caffeine.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
                isOn: caffeine.isActive,
                help: L10n.t("caffeine")
            ) {
                caffeine.toggle()
                say(L10n.t(caffeine.isActive ? "home.feedback.awakeOn" : "home.feedback.awakeOff"))
            } menu: {
                ForEach(CaffeineService.Span.allCases) { span in
                    Button(span.minutes.map { L10n.t("caffeine.minutes", $0) } ?? L10n.t("caffeine.indefinite")) {
                        // The span is fixed when the assertion is taken, so a
                        // running one has to be dropped and taken again.
                        if caffeine.isActive { caffeine.stop() }
                        caffeine.span = span
                        caffeine.toggle()
                        say(L10n.t("home.feedback.awakeOn"))
                    }
                }
            }

            KalfaQuickToggle(
                L10n.t("quick.presentation"),
                symbol: "rectangle.on.rectangle",
                isOn: presentation.isOn,
                help: L10n.t("presentation")
            ) {
                presentation.toggle()
                say(L10n.t(presentation.isOn ? "home.feedback.presentationOn" : "home.feedback.presentationOff"))
            }

            KalfaQuickToggle(
                L10n.t("quick.scroll"),
                symbol: "computermouse",
                isOn: scroll.isEnabled,
                help: L10n.t("scroll")
            ) {
                scroll.isEnabled.toggle()
                say(L10n.t(scroll.isEnabled ? "home.feedback.scrollOn" : "home.feedback.scrollOff"))
            }

            KalfaQuickToggle(
                L10n.t("quick.dock"),
                symbol: "dock.rectangle",
                isOn: dockLock.isEnabled,
                tone: dockLock.isEnabled && !dockLock.isTrusted ? .warn : .accent,
                help: dockLock.isEnabled && !dockLock.isTrusted
                    ? L10n.t("home.state.needsPermission")
                    : L10n.t("dock.mode.\(dockLock.mode.rawValue)")
            ) {
                setDockMode(dockLock.isEnabled ? .off : lastDockMode)
            } menu: {
                ForEach(DockLockService.Mode.allCases, id: \.self) { mode in
                    Button { setDockMode(mode) } label: {
                        if mode == dockLock.mode {
                            Label(L10n.t("dock.mode.\(mode.rawValue)"), systemImage: "checkmark")
                        } else {
                            Text(L10n.t("dock.mode.\(mode.rawValue)"))
                        }
                    }
                }
            }

            KalfaQuickToggle(
                L10n.t("quick.dpi"),
                symbol: dpi.isActive ? "lock.shield.fill" : "lock.shield",
                isOn: EzDPI.mode != .off,
                help: L10n.t("dpi.mode.\(EzDPI.mode.rawValue)")
            ) {
                setDPIMode(EzDPI.mode == .off ? .auto : .off)
            } menu: {
                ForEach(EzDPI.Mode.allCases, id: \.self) { mode in
                    Button { setDPIMode(mode) } label: {
                        if mode == EzDPI.mode {
                            Label(L10n.t("dpi.mode.\(mode.rawValue)"), systemImage: "checkmark")
                        } else {
                            Text(L10n.t("dpi.mode.\(mode.rawValue)"))
                        }
                    }
                }
            }
        }
    }

    /// The mode a click on the Dock switch turns back on: whichever one was in
    /// use last, so the click undoes the click before it.
    private var lastDockMode: DockLockService.Mode {
        UserDefaults.standard.string(forKey: "dockLastMode")
            .flatMap(DockLockService.Mode.init(rawValue:)) ?? .main
    }

    private func setDockMode(_ mode: DockLockService.Mode) {
        if mode != .off { UserDefaults.standard.set(mode.rawValue, forKey: "dockLastMode") }
        dockLock.mode = mode
        if dockLock.isEnabled && !dockLock.isTrusted { dockLock.requestPermission() }
        say(L10n.t("home.feedback.dockMode", L10n.t("dock.mode.\(mode.rawValue)")))
    }

    private func setDPIMode(_ mode: EzDPI.Mode) {
        EzDPI.mode = mode
        say(L10n.t("home.feedback.dpiMode", L10n.t("dpi.mode.\(mode.rawValue)")))
    }

    // MARK: Subjects

    private var subjects: some View {
        VStack(spacing: 0) {
            KalfaNavRow(L10n.t("tab.display"), value: modeSummary) { route = .display }
            KalfaDivider()
            scenes
            KalfaDivider()
            KalfaNavRow(L10n.t("monitor"), value: monitorSummary) { route = .monitor }
        }
        .kalfaGroup()
        .clipShape(RoundedRectangle(cornerRadius: KalfaDesign.groupRadius, style: .continuous))
    }

    /// Scenes saved for the arrangement that is plugged in, one click each.
    private var scenes: some View {
        let matching = center.profiles.profiles(for: center.setKey)
        return HStack(spacing: KalfaDesign.xs) {
            Text(L10n.t("profiles"))
                .font(KalfaDesign.headingFont)
            Spacer(minLength: KalfaDesign.s)
            if matching.isEmpty {
                Text(L10n.t("profiles.none.short"))
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.secondary)
            }
            ForEach(matching.prefix(3)) { profile in
                Button(profile.name) {
                    Task {
                        let ok = await center.apply(profile)
                        say(L10n.t(ok ? "home.feedback.sceneApplied" : "home.feedback.sceneFailed", profile.name))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .lineLimit(1)
                .disabled(center.isApplying)
            }
            KalfaIconButton(systemName: "plus", help: L10n.t("profiles.saveCurrent")) {
                showingSaveSheet = true
            }
            .disabled(center.screens.isEmpty || center.isApplying)
        }
        .padding(.leading, KalfaDesign.m)
        .padding(.trailing, KalfaDesign.xs)
        .padding(.vertical, KalfaDesign.xs)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: KalfaDesign.xs) {
            Button {
                CommandPalette.shared.show()
            } label: {
                HStack(spacing: KalfaDesign.xs) {
                    Image(systemName: "magnifyingglass")
                    Text(L10n.t("panel.search"))
                    Text(HotkeyService.shared.label(for: .commandPalette))
                        .foregroundStyle(.tertiary)
                }
                .font(KalfaDesign.captionFont)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t("palette.title"))

            Spacer(minLength: KalfaDesign.s)

            if center.isApplying {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(L10n.t("status.applying"))
            }

            if issueCount > 0 {
                Button {
                    KalfaWindow.show(.health)
                } label: {
                    Label(L10n.t("panel.warnings", issueCount), systemImage: "exclamationmark.triangle.fill")
                        .font(KalfaDesign.captionFont)
                        .foregroundStyle(KalfaTone.warn.color)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.t("health.title"))
            }

            KalfaIconButton(systemName: "macwindow", help: L10n.t("window.open")) {
                KalfaWindow.show()
            }
            KalfaIconButton(systemName: "power", help: L10n.t("footer.quit")) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// Things the health page would show in orange or red.
    private var issueCount: Int {
        health.checks.filter { $0.level == .problem || $0.level == .warning }.count
    }

    // MARK: Inner pages

    private func page<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: KalfaDesign.m) {
            Button {
                route = .home
            } label: {
                HStack(spacing: KalfaDesign.xs) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(KalfaDesign.titleFont)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(L10n.t("panel.back"))

            content()
        }
    }

    private var displayPage: some View {
        page(L10n.t("tab.display")) {
            if let pending = center.pendingRevert {
                revertBanner(pending)
            }
            if center.screens.count > 1 {
                screenPicker
            }
            if let screen {
                DisplayHeader(screen: screen)
                // Laid out directly rather than in a ScrollView: inside a
                // MenuBarExtra window a ScrollView resolves to zero ideal
                // height and silently swallows its content.
                VStack(alignment: .leading, spacing: KalfaDesign.s) {
                    DisplayRows(screen: screen, includesBrightness: false)
                }
                .padding(KalfaDesign.m)
                .kalfaGroup()
            } else {
                Text(L10n.t("empty.displays"))
                    .font(KalfaDesign.bodyFont)
                    .foregroundStyle(.secondary)
            }

            if let message = center.statusMessage {
                Text(message)
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(L10n.t("header.rescan"), systemImage: "arrow.clockwise") {
                    center.refreshNow()
                    center.syncBrightness()
                }
                Spacer()
                Button(L10n.t("panel.allSettings")) { KalfaWindow.show(.displays) }
            }
            .buttonStyle(.borderless)
            .font(KalfaDesign.captionFont)
        }
    }

    private var monitorPage: some View {
        page(L10n.t("monitor")) {
            MonitorCardView()
            HStack {
                Spacer()
                Button(L10n.t("upkeep.title")) { KalfaWindow.show(.upkeep) }
                    .buttonStyle(.borderless)
                    .font(KalfaDesign.captionFont)
            }
        }
    }

    // MARK: Revert banner

    /// Shown while an unproven mode is on screen. Wording leads with the question
    /// because the reader may be squinting at a barely-legible display.
    private func revertBanner(_ pending: DisplayCenter.PendingRevert) -> some View {
        VStack(alignment: .leading, spacing: KalfaDesign.s) {
            Text(L10n.t("revert.title"))
                .font(KalfaDesign.headingFont)
            Text(L10n.t(
                "revert.body",
                pending.screenName, pending.applied.summary, pending.secondsLeft
            ))
            .font(KalfaDesign.captionFont)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L10n.t("revert.keep")) { center.confirmPendingMode() }
                    .keyboardShortcut(.defaultAction)
                Button(L10n.t("revert.undo")) { Task { await center.revertPendingMode() } }
            }
        }
        .padding(KalfaDesign.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            KalfaTone.warn.color.opacity(0.16),
            in: RoundedRectangle(cornerRadius: KalfaDesign.groupRadius, style: .continuous)
        )
    }

    private func say(_ message: String) {
        feedback = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if feedback == message { feedback = nil }
        }
    }

    // MARK: Summaries

    private var monitorSummary: String {
        guard !monitor.cpuHistory.isEmpty else { return L10n.t("monitor.summary.idle") }
        return L10n.t("monitor.summary",
                      Int(monitor.sample.cpu.total * 100),
                      Int(monitor.sample.memory.usedFraction * 100))
    }

    private var modeSummary: String {
        guard let screen else { return L10n.t("header.noDisplays") }
        return center.currentMode(for: screen)?.summary ?? screen.name
    }
}
