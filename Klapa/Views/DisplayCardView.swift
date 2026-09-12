import SwiftUI

/// One display: what it is running now, what else it can run, and — for external
/// panels that answer DDC — its hardware brightness and contrast.
struct DisplayCardView: View {

    @Environment(DisplayCenter.self) private var center
    let screen: ScreenInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            title
            currentModeLine
            ModePickerView(screen: screen)
            ScaleToggleView(screen: screen)

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
            if screen.isMain { TagPill("ana", tint: .accentColor) }
            if screen.isMirrored { TagPill("yansıma", tint: .orange) }
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
                // The point of the app: say out loud when the active timing is one
                // macOS synthesised rather than one the monitor advertises.
                if !mode.isNativeTiming {
                    TagPill("türetilmiş zamanlama", tint: .orange)
                }
            }
        } else {
            Text("Aktif mod okunamadı")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Small pill used for "ana", "yansıma", "türetilmiş zamanlama".
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
