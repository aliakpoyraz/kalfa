import SwiftUI
import KalfaUI

/// Sound: which speakers, which microphone, how loud, and the mute the system
/// itself does not offer.
struct AudioTabView: View {

    private let audio = AudioService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if audio.outputs.isEmpty && audio.inputs.isEmpty {
                Text(L10n.t("audio.none"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                DevicePicker(
                    title: L10n.t("audio.output"),
                    icon: "speaker.wave.2.fill",
                    devices: audio.outputs,
                    selection: audio.currentOutput
                ) { audio.select($0, direction: .output) }

                LevelSlider(
                    value: Binding(get: { audio.volume }, set: { audio.volume = $0 }),
                    quiet: "speaker.fill",
                    loud: "speaker.wave.3.fill",
                    enabled: audio.currentOutput != nil
                )

                Divider()

                DevicePicker(
                    title: L10n.t("audio.input"),
                    icon: "mic.fill",
                    devices: audio.inputs,
                    selection: audio.currentInput
                ) { audio.select($0, direction: .input) }

                LevelSlider(
                    value: Binding(get: { audio.inputVolume }, set: { audio.inputVolume = $0 }),
                    quiet: "mic",
                    loud: "mic.fill",
                    enabled: audio.canSetInputVolume && !audio.isInputMuted
                )

                SwitchRow(
                    L10n.t("audio.mute"),
                    value: HotkeyService.shared.label(for: .muteInput),
                    isOn: Binding(get: { audio.isInputMuted }, set: { audio.setInputMuted($0) }),
                    isEnabled: audio.currentInput != nil,
                    help: L10n.t("audio.mute.help")
                )

                Text(L10n.t("audio.memory.help"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                if #available(macOS 14.2, *) {
                    AppAudioMixerSection()
                } else {
                    Text(L10n.t("mixer.unsupported"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A menu rather than a row per device: the list is as long as whatever is
/// plugged in, and a panel that grows a line every time a monitor or a pair of
/// headphones appears is a panel that jumps around under the cursor.
struct DevicePicker: View {
    let title: String
    let icon: String
    let devices: [AudioService.Device]
    let selection: AudioService.Device?
    let select: (AudioService.Device) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(title)
                .font(.caption)

            Spacer(minLength: 8)

            Menu {
                ForEach(devices) { device in
                    Button {
                        select(device)
                    } label: {
                        if device.id == selection?.id {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            } label: {
                Text(selection?.name ?? L10n.t("audio.none.short"))
                    .font(.caption)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(devices.isEmpty)
        }
    }
}

struct LevelSlider: View {
    let value: Binding<Double>
    let quiet: String
    let loud: String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: quiet)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Slider(value: value, in: 0...1)
            Image(systemName: loud)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}
