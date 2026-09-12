import SwiftUI

/// The two switches that decide how a display actually looks: Retina or not, and
/// fast or not. Both keep the logical resolution where it is.
struct ScaleToggleView: View {

    @Environment(DisplayCenter.self) private var center
    let screen: ScreenInfo

    var body: some View {
        VStack(spacing: 6) {
            hiDPIRow
            refreshRow
        }
    }

    // MARK: HiDPI

    /// Flipping this keeps the desktop size and only changes the backing store —
    /// 2560 × 1440 drawn into 5120 × 2880 pixels instead of 2560 × 1440. That is
    /// the whole difference between a Retina desktop and a blurry one.
    private var hiDPIRow: some View {
        SwitchRow(
            "HiDPI (Retina)",
            value: center.currentMode(for: screen).map { $0.pixelLabel + " px" },
            isOn: Binding(
                get: { center.currentMode(for: screen)?.isHiDPI ?? false },
                set: { _ in apply(scaleTarget) }
            ),
            isEnabled: scaleTarget != nil && !center.isApplying,
            help: scaleHelp
        ) {
            if let scaleTarget, scaleTarget.isExtended {
                TagPill("gizli mod", tint: .orange)
            }
        }
    }

    private var scaleTarget: ScreenMode? {
        guard let current = center.currentMode(for: screen) else { return nil }
        return ModeService.scaleSibling(of: current, hiDPI: !current.isHiDPI, on: screen.displayID)
    }

    private var scaleHelp: String {
        guard let current = center.currentMode(for: screen) else { return "" }
        guard let scaleTarget else {
            return "\(current.resolutionLabel) için bu ekranda karşıt ölçek yok."
        }
        let direction = current.isHiDPI ? "Kapat" : "Aç"
        return "\(direction): \(scaleTarget.pixelLabel) px arka tampon, \(scaleTarget.refreshLabel)"
    }

    // MARK: Refresh rate

    private var refreshRow: some View {
        SwitchRow(
            "Yüksek yenileme hızı",
            value: center.currentMode(for: screen)?.refreshLabel,
            isOn: Binding(
                get: { isAtPeakRefresh },
                set: { wantsFast in apply(refreshTarget(fastest: wantsFast)) }
            ),
            isEnabled: refreshTarget(fastest: !isAtPeakRefresh) != nil && !center.isApplying,
            help: refreshHelp
        )
    }

    private var isAtPeakRefresh: Bool {
        guard let current = center.currentMode(for: screen) else { return false }
        let peak = ModeService.peakRefreshRate(for: current, on: screen.displayID)
        return Int(current.refreshRate.rounded()) >= Int(peak.rounded())
    }

    private func refreshTarget(fastest: Bool) -> ScreenMode? {
        guard let current = center.currentMode(for: screen) else { return nil }
        return ModeService.refreshSibling(of: current, fastest: fastest, on: screen.displayID)
    }

    private var refreshHelp: String {
        guard let current = center.currentMode(for: screen) else { return "" }
        let peak = ModeService.peakRefreshRate(for: current, on: screen.displayID)
        return isAtPeakRefresh
            ? "Kapat: 60 Hz'e düşer"
            : "Aç: \(Int(peak.rounded())) Hz"
    }

    // MARK: -

    private func apply(_ mode: ScreenMode?) {
        guard let mode else { return }
        Task { await center.apply(mode, to: screen) }
    }
}
