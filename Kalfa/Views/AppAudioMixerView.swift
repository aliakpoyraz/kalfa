import AppKit
import SwiftUI

@available(macOS 14.2, *)
struct AppAudioMixerSection: View {
    private let mixer = AppAudioMixer.shared
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 8) {
                if mixer.processes.isEmpty {
                    Text(L10n.t("mixer.empty.detail"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ForEach(mixer.processes) { process in
                        MixerProcessRow(process: process)
                    }
                }

                HStack {
                    if let message = mixer.statusMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(L10n.t("mixer.reset")) { mixer.resetAll() }
                        .font(.caption)
                    Button { mixer.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help(L10n.t("mixer.refresh"))
                }
            }
            .padding(.top, 8)
        } label: {
            Label(L10n.t("mixer.title"), systemImage: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
        }
        // Metering taps every app that is playing, so it only runs while someone
        // is looking at the meters.
        .onAppear {
            mixer.start()
            mixer.setMonitoring(expanded)
        }
        .onDisappear { mixer.setMonitoring(false) }
        .onChange(of: expanded) { mixer.setMonitoring(expanded) }
    }
}

@available(macOS 14.2, *)
private struct MixerProcessRow: View {
    let process: AppAudioMixer.Process
    private let mixer = AppAudioMixer.shared
    private let audio = AudioService.shared

    var body: some View {
        let level = mixer.level(for: process)
        VStack(spacing: 5) {
            HStack(spacing: 9) {
                Image(nsImage: process.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(process.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int((level * 100).rounded()))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    Slider(
                        value: Binding(
                            get: { mixer.level(for: process) },
                            set: { mixer.setLevel($0, for: process) }
                        ),
                        in: 0...1
                    )
                    .controlSize(.mini)
                    MeterBar(value: mixer.meter(for: process), isMuted: level == 0)
                }

                Button { mixer.toggleMute(for: process) } label: {
                    Image(systemName: level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 18)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(level == 0 ? .red : .secondary)
                .help(level == 0 ? L10n.t("mixer.unmute") : L10n.t("mixer.mute"))
            }

            outputPicker
        }
        .padding(8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// Where this one app plays. "System" means it follows whatever everything
    /// else is doing, which is what almost every app should stay on.
    private var outputPicker: some View {
        HStack(spacing: 6) {
            Image(systemName: mixer.deviceUID(for: process) == nil ? "speaker.wave.2" : "arrow.triangle.branch")
                .font(.caption2)
                .foregroundStyle(mixer.deviceUID(for: process) == nil ? .tertiary : .secondary)
                .frame(width: 18)

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
            .controlSize(.mini)
            .font(.caption2)
        }
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
                    .fill(isMuted ? Color.red.opacity(0.5) : Color.accentColor)
                    .frame(width: max(0, min(1, value)) * geometry.size.width)
                    .animation(.linear(duration: 0.06), value: value)
            }
        }
        .frame(height: 3)
    }
}
