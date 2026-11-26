import SwiftUI
import KalfaUI

/// Sound: which speakers, which microphone, how loud, and the mute the system
/// itself does not offer.
struct AudioPage: View {

    private let audio = AudioService.shared

    var body: some View {
        Form {
            if audio.outputs.isEmpty && audio.inputs.isEmpty {
                Section {
                    Text(L10n.t("audio.none")).foregroundStyle(.secondary)
                }
            } else {
                Section(L10n.t("audio.output")) {
                    devicePicker(audio.outputs, selection: audio.currentOutput) {
                        audio.select($0, direction: .output)
                    }
                    KalfaSlider(
                        value: Binding(get: { audio.volume * 100 }, set: { audio.volume = $0 / 100 }),
                        in: 0...100,
                        symbol: audio.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        label: L10n.t("audio.output"),
                        valueText: "\(Int((audio.volume * 100).rounded()))",
                        isEnabled: audio.currentOutput != nil
                    )
                }

                Section {
                    devicePicker(audio.inputs, selection: audio.currentInput) {
                        audio.select($0, direction: .input)
                    }
                    KalfaSlider(
                        value: Binding(get: { audio.inputVolume * 100 }, set: { audio.inputVolume = $0 / 100 }),
                        in: 0...100,
                        symbol: audio.isInputMuted ? "mic.slash.fill" : "mic.fill",
                        label: L10n.t("audio.input"),
                        valueText: "\(Int((audio.inputVolume * 100).rounded()))",
                        isEnabled: audio.canSetInputVolume && !audio.isInputMuted
                    )
                    Toggle(isOn: Binding(get: { audio.isInputMuted }, set: { audio.setInputMuted($0) })) {
                        Text(L10n.t("audio.mute"))
                        Text(HotkeyService.shared.label(for: .muteInput))
                    }
                    .disabled(audio.currentInput == nil)
                    .help(L10n.t("audio.mute.help"))
                } header: {
                    Text(L10n.t("audio.input"))
                } footer: {
                    Text(L10n.t("audio.memory.help")).kalfaFootnote()
                }

                if #available(macOS 14.2, *) {
                    AppAudioMixerSection()
                } else {
                    Section(L10n.t("mixer.title")) {
                        Text(L10n.t("mixer.unsupported")).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .kalfaForm()
    }

    /// A menu rather than a row per device: the list is as long as whatever is
    /// plugged in, and a page that grows a line every time a pair of headphones
    /// appears is a page that jumps around under the pointer.
    private func devicePicker(
        _ devices: [AudioService.Device],
        selection: AudioService.Device?,
        select: @escaping (AudioService.Device) -> Void
    ) -> some View {
        Picker(L10n.t("audio.device"), selection: Binding(
            get: { selection?.id },
            set: { id in devices.first { $0.id == id }.map(select) }
        )) {
            if selection == nil {
                Text(L10n.t("audio.none.short")).tag(AudioService.Device.ID?.none)
            }
            ForEach(devices) { device in
                Text(device.name).tag(Optional(device.id))
            }
        }
        .disabled(devices.isEmpty)
    }
}
