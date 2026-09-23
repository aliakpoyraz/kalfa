import EzDPIKit
import SwiftUI
import KalfaUI

/// Names a new scene and decides how much of the machine's state rides along.
struct SaveProfileView: View {

    @Environment(DisplayCenter.self) private var center
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var includeBrightness = false
    @State private var includeAudio = false
    @State private var includeDPI = false
    @State private var includeCaffeine = false
    @State private var autoApply = true
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("save.title"))
                .font(.headline)

            TextField(L10n.t("save.name"), text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(center.screens) { screen in
                    HStack(spacing: 6) {
                        Image(systemName: screen.isBuiltIn ? "laptopcomputer" : "display")
                            .foregroundStyle(.secondary)
                        Text(screen.name)
                            .font(.caption)
                        Spacer()
                        Text(center.currentMode(for: screen)?.summary ?? "—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            Toggle(L10n.t("save.autoApply"), isOn: $autoApply)
                .font(.caption)

            if hasDDCCapableScreen {
                Toggle(L10n.t("save.includeBrightness"), isOn: $includeBrightness)
                    .font(.caption)
                    .help(L10n.t("save.includeBrightness.help"))
            }

            // Left off by default, every one of them: a scene that quietly moves
            // the sound or flips the DPI switch is a scene nobody trusts twice.
            if let output = AudioService.shared.currentOutput {
                Toggle(L10n.t("save.includeAudio", output.name), isOn: $includeAudio)
                    .font(.caption)
            }
            Toggle(L10n.t("save.includeDPI", dpiModeLabel), isOn: $includeDPI)
                .font(.caption)
            Toggle(L10n.t("save.includeCaffeine"), isOn: $includeCaffeine)
                .font(.caption)

            HStack {
                Spacer()
                Button(L10n.t("save.cancel")) { dismiss() }
                Button(L10n.t("save.confirm"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || saving)
            }
        }
        .padding(18)
        .frame(width: 340)
        .onAppear { if name.isEmpty { name = center.suggestedProfileName() } }
        .overlay {
            if saving {
                ProgressView()
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var dpiModeLabel: String {
        switch EzDPI.mode {
        case .auto: return L10n.t("dpi.mode.auto")
        case .on: return L10n.t("dpi.mode.on")
        case .off: return L10n.t("dpi.mode.off")
        }
    }

    private var hasDDCCapableScreen: Bool {
        DDCService.shared.isSupported && center.screens.contains(where: \.supportsDDC)
    }

    private func save() {
        guard !trimmedName.isEmpty, !saving else { return }
        saving = true
        Task {
            var profile = await center.captureProfile(
                named: trimmedName,
                includeBrightness: includeBrightness,
                includeAudio: includeAudio,
                includeDPI: includeDPI,
                includeCaffeine: includeCaffeine
            )
            if !autoApply {
                profile.autoApply = false
                center.profiles.update(profile)
            }
            saving = false
            dismiss()
        }
    }
}
