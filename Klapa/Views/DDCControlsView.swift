import SwiftUI

/// Hardware brightness and contrast sliders for one external display.
///
/// Values are read once when the panel opens; a monitor that does not answer gets
/// a plain explanation instead of dead controls. Slider drags are coalesced —
/// DDC/CI is a slow serial bus and a write per frame makes monitors stutter or
/// ignore the stream entirely.
struct DDCControlsView: View {

    let screen: ScreenInfo

    @State private var brightness: Double?
    @State private var contrast: Double?
    @State private var probeFinished = false
    @State private var writeTask: Task<Void, Never>?

    var body: some View {
        Group {
            if !probeFinished {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("ddc.probing"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if brightness == nil && contrast == nil {
                Text(L10n.t("ddc.noResponse"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    if brightness != nil {
                        slider(
                            icon: "sun.max",
                            help: L10n.t("ddc.brightness"),
                            value: Binding(
                                get: { brightness ?? 0 },
                                set: { brightness = $0; schedule(.brightness, $0) }
                            )
                        )
                    }
                    if contrast != nil {
                        slider(
                            icon: "circle.lefthalf.filled",
                            help: L10n.t("ddc.contrast"),
                            value: Binding(
                                get: { contrast ?? 0 },
                                set: { contrast = $0; schedule(.contrast, $0) }
                            )
                        )
                    }
                }
            }
        }
        .task(id: screen.displayID) { await probe() }
        .onDisappear { writeTask?.cancel() }
    }

    private func slider(icon: String, help: String, value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .help(help)
            Slider(value: value, in: 0...100)
            Text("\(Int(value.wrappedValue))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
        }
    }

    private func probe() async {
        probeFinished = false
        let ddc = DDCService.shared
        let readBrightness = await ddc.read(.brightness, from: screen.displayID)
        let readContrast = await ddc.read(.contrast, from: screen.displayID)
        brightness = readBrightness.map { Double($0.percent) }
        contrast = readContrast.map { Double($0.percent) }
        probeFinished = true
    }

    /// Coalesces rapid slider updates into one write per quiet 80 ms.
    private func schedule(_ feature: DDCService.VCP, _ value: Double) {
        writeTask?.cancel()
        let displayID = screen.displayID
        writeTask = Task {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            await DDCService.shared.write(feature, percent: Int(value), to: displayID)
        }
    }
}
