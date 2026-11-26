import AppKit
import SwiftUI
import KalfaUI

/// Per-app volume and routing, as a section of the Sound form.
@available(macOS 14.2, *)
struct AppAudioMixerSection: View {
    private let mixer = AppAudioMixer.shared

    var body: some View {
        Section {
            if mixer.processes.isEmpty {
                Text(L10n.t("mixer.empty.detail"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(mixer.processes) { process in
                    MixerProcessRow(process: process)
                }
            }

            HStack {
                if let message = mixer.statusMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(KalfaDesign.captionFont)
                        .foregroundStyle(KalfaTone.warn.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(L10n.t("mixer.reset")) { mixer.resetAll() }
                Button { mixer.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help(L10n.t("mixer.refresh"))
            }
        } header: {
            Text(L10n.t("mixer.title"))
        }
        // Metering taps every app that is playing, so it only runs while someone
        // is looking at the meters.
        .onAppear {
            mixer.start()
            mixer.setMonitoring(true)
        }
        .onDisappear { mixer.setMonitoring(false) }
    }
}

@available(macOS 14.2, *)
private struct MixerProcessRow: View {
    let process: AppAudioMixer.Process
    private let mixer = AppAudioMixer.shared
    private let audio = AudioService.shared

    var body: some View {
        let level = mixer.level(for: process)
        HStack(spacing: KalfaDesign.m) {
            Image(nsImage: process.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(process.name)
                    .font(KalfaDesign.bodyFont)
                    .lineLimit(1)
                outputPicker
            }
            .frame(width: 150, alignment: .leading)

            VStack(spacing: KalfaDesign.xs) {
                KalfaSlider(
                    value: Binding(
                        get: { mixer.level(for: process) * 100 },
                        set: { mixer.setLevel($0 / 100, for: process) }
                    ),
                    in: 0...100,
                    symbol: level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    label: process.name,
                    valueText: "\(Int((level * 100).rounded()))"
                )
                MeterBar(value: mixer.meter(for: process), isMuted: level == 0)
                    .padding(.leading, 26)
                    .padding(.trailing, 36)
            }

            Button { mixer.toggleMute(for: process) } label: {
                Image(systemName: level == 0 ? "speaker.slash" : "speaker")
            }
            .buttonStyle(.borderless)
            .help(level == 0 ? L10n.t("mixer.unmute") : L10n.t("mixer.mute"))
        }
    }

    /// Where this one app plays. "System" means it follows whatever everything
    /// else is doing, which is what almost every app should stay on.
    private var outputPicker: some View {
        Picker("", selection: Binding(
            get: { mixer.deviceUID(for: process) ?? "" },
            set: { mixer.setDevice($0.isEmpty ? nil : $0, for: process) }
        )) {
            Text(L10n.t("mixer.device.system")).tag("")
            ForEach(audio.outputs) { device in
                Text(device.name).tag(device.uid)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
    }
}

/// A peak meter. Deliberately not a level readout: the point is to answer "which
/// of these is the one making noise?" at a glance.
private struct MeterBar: View {
    let value: Double
    let isMuted: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(isMuted ? KalfaTone.bad.color.opacity(0.5) : Color.accentColor)
                    .frame(width: max(0, min(1, value)) * geometry.size.width)
                    .animation(.linear(duration: 0.06), value: value)
            }
        }
        .frame(height: 3)
    }
}
