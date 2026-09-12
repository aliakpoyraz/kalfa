import SwiftUI

/// Names a new profile and decides whether DDC values ride along.
struct SaveProfileView: View {

    @Environment(DisplayCenter.self) private var center
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var includeBrightness = false
    @State private var autoApply = true
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Profili kaydet")
                .font(.headline)

            TextField("Profil adı", text: $name)
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

            Toggle("Bu dizilim bağlandığında kendiliğinden uygula", isOn: $autoApply)
                .font(.caption)

            if hasDDCCapableScreen {
                Toggle("Parlaklık ve kontrastı da kaydet", isOn: $includeBrightness)
                    .font(.caption)
                    .help("Kaydetme sırasında her monitöre DDC sorgusu gider; birkaç saniye sürebilir.")
            }

            HStack {
                Spacer()
                Button("Vazgeç") { dismiss() }
                Button("Kaydet", action: save)
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

    private var hasDDCCapableScreen: Bool {
        DDCService.shared.isSupported && center.screens.contains(where: \.supportsDDC)
    }

    private func save() {
        guard !trimmedName.isEmpty, !saving else { return }
        saving = true
        Task {
            var profile = await center.captureProfile(
                named: trimmedName,
                includeBrightness: includeBrightness
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
