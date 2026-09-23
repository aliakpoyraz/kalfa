import SwiftUI
import KalfaUI

/// Resolution menu, grouped the way a person thinks about it: pick a size, then a
/// refresh rate. A flat list is unusable — a 1440p monitor commonly exposes 80+
/// modes once HiDPI variants are included.
struct ModePickerView: View {

    @Environment(DisplayCenter.self) private var center
    let screen: ScreenInfo

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t("resolution"))
                    .font(.caption)
                Text(center.currentMode(for: screen)?.resolutionLabel ?? "—")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let native = nativeMode, shouldOfferNative(native) {
                Button(L10n.t("resolution.monitorMode")) { apply(native) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help(L10n.t("resolution.monitorMode.help", native.summary))
                    .disabled(center.isApplying)
            }

            Menu {
                ForEach(groups) { group in
                    groupItem(group)
                }
            } label: {
                Text(L10n.t("resolution.change"))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(.caption)
            .disabled(center.isApplying || groups.isEmpty)
        }
    }

    // MARK: Menu content

    @ViewBuilder
    private func groupItem(_ group: ModeGroup) -> some View {
        if group.modes.count == 1, let only = group.modes.first {
            Button { apply(only) } label: {
                Text(label(for: only, in: group))
            }
        } else {
            Menu(group.label) {
                ForEach(group.modes) { mode in
                    Button { apply(mode) } label: {
                        Text(label(for: mode, in: group))
                    }
                }
            }
        }
    }

    /// Inside a resolution group the size is redundant, so only the rate and the
    /// warning markers are shown.
    private func label(for mode: ScreenMode, in group: ModeGroup) -> String {
        var text = group.modes.count == 1 ? mode.summary : mode.refreshLabel
        if mode.id == center.currentMode(for: screen)?.id { text = "✓ " + text }
        // Softness is the thing most worth knowing before picking, so it leads.
        if center.rendering(of: mode, on: screen)?.isSoft == true { text += L10n.t("mode.suffix.soft") }
        if mode.isExtended { text += L10n.t("mode.suffix.hiddenHiDPI") }
        else if !mode.isNativeTiming { text += L10n.t("mode.suffix.derived") }
        if mode.isHidden { text += L10n.t("mode.suffix.neverShown") }
        return text
    }

    private func apply(_ mode: ScreenMode) {
        Task { await center.apply(mode, to: screen) }
    }

    // MARK: Grouping

    struct ModeGroup: Identifiable {
        let id: String
        let label: String
        let modes: [ScreenMode]
    }

    /// The shortcut is only worth showing when the display is actually off its
    /// native timing. Comparing mode IDs is not enough — a panel commonly lists
    /// the same timing twice under different IDs, which made the button appear
    /// while nothing was wrong.
    private func shouldOfferNative(_ native: ScreenMode) -> Bool {
        guard let current = center.currentMode(for: screen) else { return false }
        if current.fingerprint == native.fingerprint { return false }
        return !current.isNativeTiming
            || current.pixelWidth < native.pixelWidth
            || current.refreshRate < native.refreshRate
    }

    private var nativeMode: ScreenMode? {
        visibleModes.filter(\.isNativeTiming).max {
            ($0.pixelWidth, $0.refreshRate) < ($1.pixelWidth, $1.refreshRate)
        }
    }

    /// Applies the user's visibility preferences before grouping.
    private var visibleModes: [ScreenMode] {
        let all = center.modes(for: screen)
        let settings = center.settings

        // A "low-resolution twin" is the 1× mode of a size that also has a 2× mode.
        let hiDPISizes = Set(
            all.filter(\.isHiDPI).map { "\($0.width)x\($0.height)" }
        )

        return all.filter { mode in
            if mode.isHidden && !settings.showHiddenModes { return false }
            if mode.isStretched || mode.isTelevision { return false }
            // SkyLight-only modes are mostly duplicates of what CoreGraphics already
            // lists. The exception — and the reason the extra list is read at all —
            // is HiDPI, so only those are surfaced unless hidden modes are asked for.
            if mode.isExtended && !mode.isHiDPI && !settings.showHiddenModes { return false }
            if !settings.showLowResolutionTwins,
               !mode.isHiDPI,
               hiDPISizes.contains("\(mode.width)x\(mode.height)") {
                return false
            }
            return true
        }
    }

    private var groups: [ModeGroup] {
        var order: [String] = []
        var buckets: [String: [ScreenMode]] = [:]

        for mode in visibleModes {
            let key = "\(mode.width)x\(mode.height)x\(mode.scale)"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(mode)
        }

        return order.compactMap { key in
            guard let modes = buckets[key], let first = modes.first else { return nil }
            var label = first.resolutionLabel
            if first.isHiDPI { label += "  HiDPI" }
            if first.isNativeTiming && modes.allSatisfy(\.isNativeTiming) { label += "  ·" }
            return ModeGroup(
                id: key,
                label: label,
                modes: modes.sorted { $0.refreshRate > $1.refreshRate }
            )
        }
    }
}
