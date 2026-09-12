import SwiftUI

/// One display: what it is running now, what else it can run, what the cable is
/// carrying, and — for external panels that answer DDC — hardware brightness.
struct DisplayCardView: View {

    @Environment(DisplayCenter.self) private var center
    let screen: ScreenInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            title
            currentModeLine
            ModePickerView(screen: screen)
            ScaleToggleView(screen: screen)
            LinkRow(screen: screen)

            if screen.supportsDDC && DDCService.shared.isSupported {
                DDCControlsView(screen: screen)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private var title: some View {
        HStack(spacing: 6) {
            Image(systemName: screen.isBuiltIn ? "laptopcomputer" : "display")
                .foregroundStyle(.secondary)
            Text(screen.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            if screen.isMain { TagPill(L10n.t("display.badge.main"), tint: .accentColor) }
            if screen.isMirrored { TagPill(L10n.t("display.badge.mirrored"), tint: .orange) }
            Spacer()
        }
    }

    @ViewBuilder
    private var currentModeLine: some View {
        if let mode = center.currentMode(for: screen) {
            HStack(spacing: 6) {
                Text(mode.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Says out loud when the active timing is one macOS synthesized
                // rather than one the monitor advertises.
                if !mode.isNativeTiming {
                    TagPill(L10n.t("display.badge.derived"), tint: .orange)
                        .help(L10n.t("display.badge.derived.help"))
                }
            }
        } else {
            Text(L10n.t("display.currentUnknown"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Small pill used for the inline markers on a card.
struct TagPill: View {
    let text: String
    let tint: Color

    init(_ text: String, tint: Color) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }
}
