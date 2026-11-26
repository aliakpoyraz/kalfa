import SwiftUI
import KalfaUI

/// Profiles for the arrangement that is plugged in right now, one per row.
///
/// Profiles saved for *other* arrangements are deliberately hidden: applying a
/// two-screen profile while one screen is unplugged can only half-work, and the
/// list stays short enough to scan.
struct ProfilesSectionView: View {

    @Environment(DisplayCenter.self) private var center
    @Binding var showingSaveSheet: Bool

    var body: some View {
        Group {
            if matching.isEmpty {
                Text(L10n.t("profiles.none"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(matching) { profile in
                    row(profile)
                }
            }

            HStack {
                Button(L10n.t("profiles.saveCurrent"), systemImage: "plus") {
                    showingSaveSheet = true
                }
                .disabled(center.screens.isEmpty || center.isApplying)
                Spacer()
                if otherCount > 0 {
                    Text(L10n.t("profiles.otherLayouts", otherCount)).kalfaFootnote()
                }
            }
        }
    }

    private func row(_ profile: Profile) -> some View {
        KalfaSettingRow(profile.name, detail: summary(profile)) {
            Button(L10n.t("profiles.apply")) {
                Task { await center.apply(profile) }
            }
            .disabled(center.isApplying)

            Button(role: .destructive) {
                center.profiles.remove(profile)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(L10n.t("profiles.delete"))

            KalfaSwitch(Binding(
                get: { profile.autoApply },
                set: { newValue in
                    var copy = profile
                    copy.autoApply = newValue
                    center.profiles.update(copy)
                }
            ))
            .help(L10n.t("profiles.autoApply.help"))
        }
    }

    private func summary(_ profile: Profile) -> String {
        let modes = profile.entries.map { entry in
            "\(entry.mode.width)×\(entry.mode.height) \(entry.mode.refreshRate)Hz"
        }
        var text = modes.joined(separator: ", ")
        if profile.restoresBrightness { text += L10n.t("profiles.summary.brightness") }
        if let name = profile.audioOutputName { text += " · \(name)" }
        if let raw = profile.dpiMode { text += " · DPI \(raw)" }
        if profile.caffeine == true { text += L10n.t("profiles.summary.caffeine") }
        return text
    }

    private var matching: [Profile] {
        center.profiles.profiles(for: center.setKey)
    }

    private var otherCount: Int {
        center.profiles.profiles.count - matching.count
    }
}
