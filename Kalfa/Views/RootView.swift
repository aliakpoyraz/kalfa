import EzDPIKit
import SwiftUI
import UpkeepKit
import KalfaUI

/// The menu bar panel: what the machine is doing, and the switches worth
/// flicking on the way past.
///
/// Reading down: the state line, the toggles as tiles that carry their own
/// state, then the subjects that are worth a look without sitting down —
/// displays, sound, scenes, live load, DPI. Everything that is *work* rather
/// than a flick lives in the window; everything searchable lives in the
/// palette. The panel used to carry a second copy of both and was longer than
/// the screen for it.
struct RootView: View {

    private enum Card: String {
        case displays, audio, scenes, dpi, monitor
    }

    @Environment(DisplayCenter.self) private var center
    @Environment(ScrollService.self) private var scroll

    @State private var openCard: Card?
    @State private var feedback: String?
    @State private var showingSaveSheet = false

    private let audio = AudioService.shared
    private let caffeine = CaffeineService.shared
    private let presentation = PresentationMode.shared
    /// Observed, not just held: the DPI engine's state drives the tile and the
    /// header chip, and a plain `let` would leave both stale.
    @StateObject private var dpi = EzDPIStatus()
    /// Only publishes while the monitoring card is open — it takes no samples
    /// otherwise, so the closed-card summary deliberately stays generic.
    @ObservedObject private var monitor = Upkeep.monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(alignment: .leading, spacing: KalfaDesign.s) {
                if let pending = center.pendingRevert {
                    revertBanner(pending)
                }
                tiles
                cards

                if let feedback {
                    Label(feedback, systemImage: "checkmark.circle.fill")
                        .font(KalfaDesign.captionFont)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, KalfaDesign.edge)
            .padding(.bottom, KalfaDesign.m)

            footer
        }
        .frame(width: KalfaDesign.panelWidth)
        .background(.ultraThinMaterial)
        // Rebuilds the panel when the language changes; SwiftUI cannot see into
        // the strings bundle on its own.
        .id(center.settings.language.rawValue)
        .animation(KalfaDesign.motion, value: feedback)
        .onAppear { CommandPalette.shared.center = center }
        .sheet(isPresented: $showingSaveSheet) {
            SaveProfileView()
                .environment(center)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.s) {
            HStack(spacing: KalfaDesign.s) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)

                Text(L10n.t("app.name"))
                    .font(KalfaDesign.titleFont)

                Spacer()

                if center.isApplying {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(L10n.t("status.applying"))
                }

                KalfaToolbarButton(systemName: "magnifyingglass", help: searchHelp) {
                    CommandPalette.shared.show()
                }
                KalfaToolbarButton(systemName: "stethoscope", help: L10n.t("health.title")) {
                    KalfaWindow.show(.health)
                }
                KalfaToolbarButton(systemName: "macwindow", help: L10n.t("window.open")) {
                    KalfaWindow.show()
                }
            }

            // The state line: what Kalfa would answer if asked "what is going on
            // with this Mac right now?".
            HStack(spacing: KalfaDesign.xs) {
                KalfaChip(displaySummary, symbol: center.isClamshell ? "macbook.and.iphone" : "display", tint: .blue)
                if let output = audio.currentOutput {
                    KalfaChip(output.name, symbol: "speaker.wave.2.fill", tint: .purple)
                }
                if audio.isInputMuted {
                    KalfaChip(L10n.t("home.state.muted"), symbol: "mic.slash.fill", tint: .red)
                }
                if dpi.isActive {
                    KalfaChip(L10n.t("dpi"), symbol: "lock.shield.fill", tint: .green)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, KalfaDesign.edge)
        .padding(.top, KalfaDesign.m)
        .padding(.bottom, KalfaDesign.m)
    }

    private var searchHelp: String {
        "\(L10n.t("palette.title")) · \(HotkeyService.shared.label(for: .commandPalette))"
    }

    // MARK: Tiles

    private var tiles: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: KalfaDesign.s), GridItem(.flexible(), spacing: KalfaDesign.s)],
            spacing: KalfaDesign.s
        ) {
            KalfaTile(
                title: L10n.t("home.action.microphone"),
                state: audio.isInputMuted ? L10n.t("home.state.muted") : L10n.t("home.state.ready"),
                symbol: audio.isInputMuted ? "mic.slash.fill" : "mic.fill",
                role: .audio,
                isOn: audio.isInputMuted
            ) {
                audio.setInputMuted(!audio.isInputMuted)
                say(L10n.t(audio.isInputMuted ? "home.feedback.micOff" : "home.feedback.micOn"))
            }

            KalfaTile(
                title: L10n.t("home.action.awake"),
                state: caffeine.isActive ? L10n.t("on") : L10n.t("home.state.off"),
                symbol: caffeine.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
                role: .neutral,
                isOn: caffeine.isActive
            ) {
                caffeine.toggle()
                say(L10n.t(caffeine.isActive ? "home.feedback.awakeOn" : "home.feedback.awakeOff"))
            }

            KalfaTile(
                title: L10n.t("presentation"),
                state: presentation.isOn ? L10n.t("on") : L10n.t("home.state.off"),
                symbol: "rectangle.on.rectangle",
                role: .neutral,
                isOn: presentation.isOn
            ) {
                presentation.toggle()
                say(L10n.t(presentation.isOn ? "home.feedback.presentationOn" : "home.feedback.presentationOff"))
            }

            KalfaTile(
                title: L10n.t("scroll"),
                state: scroll.isEnabled ? L10n.t("on") : L10n.t("home.state.off"),
                symbol: "computermouse",
                role: .neutral,
                isOn: scroll.isEnabled
            ) {
                scroll.isEnabled.toggle()
                say(L10n.t(scroll.isEnabled ? "home.feedback.scrollOn" : "home.feedback.scrollOff"))
            }

            KalfaTile(
                title: L10n.t("dpi"),
                state: L10n.t("dpi.mode.\(EzDPI.mode.rawValue)"),
                symbol: dpi.isActive ? "lock.shield.fill" : "lock.shield",
                role: .dpi,
                isOn: dpi.isActive
            ) {
                // Cycles the three modes in the order people actually want them:
                // automatic, forced on, off.
                let order: [EzDPI.Mode] = [.auto, .on, .off]
                let next = order[((order.firstIndex(of: EzDPI.mode) ?? 0) + 1) % order.count]
                EzDPI.mode = next
                say(L10n.t("home.feedback.dpiMode", L10n.t("dpi.mode.\(next.rawValue)")))
            }

            KalfaTile(
                title: L10n.t("upkeep.title"),
                state: L10n.t("upkeep.state"),
                symbol: "wrench.adjustable",
                role: .neutral,
                isOn: false
            ) {
                KalfaWindow.show(.upkeep)
            }
        }
    }

    // MARK: Cards

    private var cards: some View {
        VStack(spacing: KalfaDesign.s) {
            KalfaCard(
                title: L10n.t("tab.display"),
                summary: modeSummary,
                symbol: "display",
                role: .display,
                isExpanded: binding(for: .displays)
            ) {
                if center.screens.isEmpty {
                    Text(L10n.t("empty.displays"))
                        .font(KalfaDesign.bodyFont)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, KalfaDesign.m)
                } else {
                    // Laid out directly rather than in a ScrollView: inside a
                    // MenuBarExtra window a ScrollView resolves to zero ideal
                    // height and silently swallows its content.
                    ForEach(center.screens) { screen in
                        DisplayCardView(screen: screen)
                    }
                    HStack {
                        Spacer()
                        Button(L10n.t("header.rescan"), systemImage: "arrow.clockwise") {
                            center.refreshNow()
                        }
                        .buttonStyle(.borderless)
                        .font(KalfaDesign.captionFont)
                    }
                }
                if let message = center.statusMessage {
                    Text(message)
                        .font(KalfaDesign.captionFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            KalfaCard(
                title: L10n.t("tab.audio"),
                summary: audio.currentOutput?.name ?? L10n.t("audio.none.short"),
                symbol: "speaker.wave.2.fill",
                role: .audio,
                isExpanded: binding(for: .audio)
            ) {
                AudioTabView()
            }

            KalfaCard(
                title: L10n.t("profiles"),
                summary: sceneSummary,
                symbol: "sparkles.rectangle.stack",
                role: .display,
                isExpanded: binding(for: .scenes)
            ) {
                ProfilesSectionView(showingSaveSheet: $showingSaveSheet)
            }

            KalfaCard(
                title: L10n.t("monitor"),
                summary: monitorSummary,
                symbol: "gauge.with.dots.needle.33percent",
                role: .neutral,
                isExpanded: binding(for: .monitor)
            ) {
                MonitorCardView()
            }

            KalfaCard(
                title: L10n.t("tab.dpi"),
                summary: L10n.t("dpi.mode.\(EzDPI.mode.rawValue)"),
                symbol: "lock.shield",
                role: .dpi,
                isExpanded: binding(for: .dpi)
            ) {
                EzDPIPanel()
            }
        }
    }

    /// Only one card at a time: the panel is a menu, and a menu that grows past
    /// the screen is a menu you scroll instead of read.
    private func binding(for card: Card) -> Binding<Bool> {
        Binding(
            get: { openCard == card },
            set: { openCard = $0 ? card : nil }
        )
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: KalfaDesign.s) {
            Text(versionLabel)
                .font(KalfaDesign.captionFont)
                .foregroundStyle(.tertiary)
            Spacer()
            Button(L10n.t("window.open")) { KalfaWindow.show() }
                .buttonStyle(.borderless)
                .font(KalfaDesign.captionFont)
            Button(L10n.t("footer.quit")) { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(KalfaDesign.captionFont)
        }
        .padding(.horizontal, KalfaDesign.edge)
        .padding(.vertical, KalfaDesign.s)
        .background(.bar)
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
        .kalfaSurface(tint: .orange, isActive: true)
    }

    private func say(_ message: String) {
        feedback = message
    }

    // MARK: Summaries

    /// Live numbers once the card has been opened, a plain label before that.
    /// Showing "0%" while nothing is being measured would be a lie, and keeping
    /// the sampler running just to fill this line would cost more than it tells.
    private var monitorSummary: String {
        guard !monitor.cpuHistory.isEmpty else { return L10n.t("monitor.summary.idle") }
        return L10n.t("monitor.summary",
                      Int(monitor.sample.cpu.total * 100),
                      Int(monitor.sample.memory.usedFraction * 100))
    }

    private var displaySummary: String {
        let count = center.screens.count
        guard count > 0 else { return L10n.t("header.noDisplays") }
        return count == 1
            ? L10n.t("header.displayCount.one")
            : L10n.t("header.displayCount.many", count)
    }

    private var modeSummary: String {
        guard let main = center.screens.first(where: \.isMain) ?? center.screens.first else {
            return L10n.t("header.noDisplays")
        }
        guard let mode = center.currentMode(for: main) else { return main.name }
        return "\(main.name) · \(mode.summary)"
    }

    private var sceneSummary: String {
        let matching = center.profiles.profiles(for: DisplaySetKey(center.screens))
        return matching.isEmpty
            ? L10n.t("profiles.none.short")
            : L10n.t("profiles.count", matching.count)
    }

    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Kalfa \(version)"
    }
}
