import SwiftUI
import KalfaUI

/// The name of a display and what it is to the arrangement.
struct DisplayHeader: View {

    @Environment(DisplayCenter.self) private var center
    let screen: ScreenInfo

    var body: some View {
        HStack(spacing: KalfaDesign.s) {
            Image(systemName: screen.isBuiltIn ? "laptopcomputer" : "display")
                .foregroundStyle(.secondary)
            Text(screen.name)
                .font(KalfaDesign.headingFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
            if screen.isMain { KalfaBadge(L10n.t("display.badge.main")) }
            if screen.isMirrored { KalfaBadge(L10n.t("display.badge.mirrored"), tone: .warn) }
            // Says out loud when the active timing is one macOS synthesized
            // rather than one the monitor advertises.
            if let mode = center.currentMode(for: screen), !mode.isNativeTiming {
                KalfaBadge(L10n.t("display.badge.derived"), tone: .warn)
                    .help(L10n.t("display.badge.derived.help"))
            }
            Spacer(minLength: 0)
        }
    }
}

/// Everything that can be set on one display, one setting per row.
///
/// A group rather than a stack, so the rows land as separate lines whether the
/// parent is a form in the window or a padded column in the panel.
struct DisplayRows: View {

    let screen: ScreenInfo
    /// The panel already carries brightness on its front page.
    var includesBrightness = true

    var body: some View {
        Group {
            ModePickerView(screen: screen)
            ScaleToggleView(screen: screen)
            LinkRow(screen: screen)
            if includesBrightness {
                TitledSlider(L10n.t("ddc.brightness")) {
                    BrightnessSlider(screen: screen)
                }
                BrightnessNote(screen: screen)
            }
            ContrastRow(screen: screen, titled: includesBrightness)
        }
    }
}

/// A slider with its name in front, for forms where the icon alone is not
/// enough.
struct TitledSlider<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: KalfaDesign.m) {
            Text(title)
                .font(KalfaDesign.bodyFont)
                .frame(minWidth: 72, alignment: .leading)
            content
        }
        .frame(minHeight: 28)
    }
}

// MARK: - Brightness

/// One display's brightness on Kalfa's single scale: backlight above zero,
/// darkening below it.
struct BrightnessSlider: View {

    let screen: ScreenInfo
    private let brightness = BrightnessService.shared

    var body: some View {
        let range = brightness.range(for: screen)
        let level = brightness.level(for: screen)
        KalfaSlider(
            value: Binding(
                get: { brightness.level(for: screen) ?? 0 },
                set: { brightness.setLevel($0, for: screen) }
            ),
            in: range,
            zero: range.lowerBound < 0 ? 0 : nil,
            symbol: (level ?? 0) < 0 ? "moon.fill" : "sun.max.fill",
            label: L10n.t("ddc.brightness"),
            valueText: brightness.label(for: screen),
            isEnabled: level != nil
        )
    }
}

/// The line under the slider, present only when there is something to say:
/// that the picture is being darkened, or that this display has no backlight
/// control and darkening is all there is.
struct BrightnessNote: View {

    let screen: ScreenInfo
    private let brightness = BrightnessService.shared

    var body: some View {
        if brightness.backend(for: screen) == .software {
            Text(L10n.t("brightness.softwareOnly"))
                .font(KalfaDesign.captionFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if let level = brightness.level(for: screen), level < 0 {
            HStack(spacing: KalfaDesign.s) {
                Text(L10n.t("brightness.extra", Int((level / BrightnessService.lowest * 100).rounded())))
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(L10n.t("brightness.lift")) { brightness.setLevel(0, for: screen) }
                    .buttonStyle(.borderless)
                    .font(KalfaDesign.captionFont)
            }
        }
    }
}

// MARK: - Contrast

/// Hardware contrast over DDC. Absent, not disabled, on a display that does not
/// answer: a dead slider explains nothing.
struct ContrastRow: View {

    let screen: ScreenInfo
    let titled: Bool

    @State private var contrast: Double?
    @State private var writeTask: Task<Void, Never>?

    var body: some View {
        Group {
            if contrast != nil {
                if titled {
                    TitledSlider(L10n.t("ddc.contrast")) { slider }
                } else {
                    slider
                }
            }
        }
        .task(id: screen.displayID) {
            guard screen.supportsDDC, DDCService.shared.isSupported else { return }
            contrast = await DDCService.shared.read(.contrast, from: screen.displayID)
                .map { Double($0.percent) }
        }
        .onDisappear { writeTask?.cancel() }
    }

    private var slider: some View {
        KalfaSlider(
            value: Binding(
                get: { contrast ?? 0 },
                set: { contrast = $0; schedule($0) }
            ),
            in: 0...100,
            symbol: "circle.lefthalf.filled",
            label: L10n.t("ddc.contrast"),
            valueText: "\(Int(contrast ?? 0))"
        )
    }

    /// One write per quiet 80 ms; DDC drops a stream that arrives per frame.
    private func schedule(_ value: Double) {
        writeTask?.cancel()
        let displayID = screen.displayID
        writeTask = Task {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            await DDCService.shared.write(.contrast, percent: Int(value), to: displayID)
        }
    }
}
