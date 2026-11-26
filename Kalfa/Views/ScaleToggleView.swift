import SwiftUI
import KalfaUI

/// The two switches that decide how a display actually looks: Retina or not, and
/// fast or not. Both keep the logical resolution where it is.
struct ScaleToggleView: View {

    @Environment(DisplayCenter.self) private var center
    let screen: ScreenInfo

    var body: some View {
        // A group, not a stack: each row is its own line whether the parent is
        // a form in the window or a padded column in the panel.
        Group {
            hiDPIRow
            refreshRow
            if let warning = softnessWarning {
                softnessNote(warning)
            }
        }
    }

    // MARK: HiDPI

    /// Flipping this keeps the desktop size and only changes the backing store —
    /// 2560 × 1440 drawn into 5120 × 2880 pixels instead of 2560 × 1440.
    private var hiDPIRow: some View {
        KalfaSettingRow(
            L10n.t("hidpi"),
            detail: center.currentMode(for: screen).map { $0.pixelLabel + " px" },
            help: scaleHelp
        ) {
            renderingBadge
            if scaleTarget?.isExtended == true {
                KalfaBadge(L10n.t("hidpi.badge.hidden"), tone: .warn)
                    .help(L10n.t("hidpi.badge.hidden.help"))
            }
        } control: {
            KalfaSwitch(
                Binding(
                    get: { center.currentMode(for: screen)?.isHiDPI ?? false },
                    set: { _ in apply(scaleTarget) }
                ),
                isEnabled: scaleTarget != nil && !center.isApplying
            )
        }
    }

    /// Says how the current backing store reaches the glass. The fractional case
    /// is the one worth interrupting someone over — it is the difference between
    /// a sharp desktop and a soft one, and nothing in the resolution name hints
    /// at it.
    @ViewBuilder
    private var renderingBadge: some View {
        switch rendering {
        case .exact:
            KalfaBadge(L10n.t("grid.exact"), tone: .ok)
        case .supersampled(let factor):
            KalfaBadge(L10n.t("grid.supersampled", factor), tone: .ok)
        case .fractional:
            KalfaBadge(L10n.t("grid.fractional"), tone: .warn)
        case nil:
            EmptyView()
        }
    }

    private var rendering: ModeService.Rendering? {
        guard let current = center.currentMode(for: screen) else { return nil }
        return center.rendering(of: current, on: screen)
    }

    private var scaleTarget: ScreenMode? {
        guard let current = center.currentMode(for: screen) else { return nil }
        return center.scaleSibling(for: screen, hiDPI: !current.isHiDPI)
    }

    private var scaleHelp: String {
        guard let current = center.currentMode(for: screen) else { return "" }
        guard let scaleTarget else {
            return L10n.t("hidpi.noCounterpart", current.resolutionLabel)
        }
        return L10n.t(
            current.isHiDPI ? "hidpi.turnOff" : "hidpi.turnOn",
            scaleTarget.pixelLabel, scaleTarget.refreshLabel
        )
    }

    // MARK: Softness warning

    private var softnessWarning: ScreenMode? {
        guard rendering?.isSoft == true else { return nil }
        guard let sharpest = center.sharpestMode(for: screen),
              sharpest.id != center.currentMode(for: screen)?.id
        else { return nil }
        return sharpest
    }

    private func softnessNote(_ sharpest: ScreenMode) -> some View {
        HStack(alignment: .top, spacing: KalfaDesign.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(KalfaTone.warn.color)
                .font(KalfaDesign.captionFont)
            VStack(alignment: .leading, spacing: KalfaDesign.xs) {
                Text(noteText(sharpest))
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L10n.t("grid.switchTo", sharpest.resolutionLabel)) { apply(sharpest) }
                    .buttonStyle(.borderless)
                    .font(KalfaDesign.captionFont)
                    .disabled(center.isApplying)
            }
        }
    }

    private func noteText(_ sharpest: ScreenMode) -> String {
        guard let current = center.currentMode(for: screen),
              let panel = center.panelPixelSize(for: screen)
        else { return "" }
        let factor = Double(current.pixelWidth) / Double(panel.width)
        return L10n.t("grid.warning", current.pixelLabel, panel.width, panel.height, factor)
    }

    // MARK: Refresh rate

    private var refreshRow: some View {
        KalfaSettingRow(
            L10n.t("refresh"),
            detail: center.currentMode(for: screen)?.refreshLabel,
            help: refreshHelp
        ) {
            KalfaSwitch(
                Binding(
                    get: { isAtPeakRefresh },
                    set: { wantsFast in apply(center.refreshSibling(for: screen, fastest: wantsFast)) }
                ),
                isEnabled: center.refreshSibling(for: screen, fastest: !isAtPeakRefresh) != nil
                    && !center.isApplying
            )
        }
    }

    private var isAtPeakRefresh: Bool {
        guard let current = center.currentMode(for: screen),
              let peak = center.peakRefreshRate(for: screen)
        else { return false }
        return Int(current.refreshRate.rounded()) >= Int(peak.rounded())
    }

    private var refreshHelp: String {
        guard let peak = center.peakRefreshRate(for: screen) else { return "" }
        return isAtPeakRefresh
            ? L10n.t("refresh.off")
            : L10n.t("refresh.on", Int(peak.rounded()))
    }

    // MARK: -

    private func apply(_ mode: ScreenMode?) {
        guard let mode else { return }
        Task { await center.apply(mode, to: screen) }
    }
}
