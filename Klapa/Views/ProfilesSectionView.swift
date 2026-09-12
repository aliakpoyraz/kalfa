import SwiftUI

/// Profiles for the arrangement that is plugged in right now.
///
/// Profiles saved for *other* arrangements are deliberately hidden: applying a
/// two-screen profile while one screen is unplugged can only half-work, and the
/// list stays short enough to scan.
struct ProfilesSectionView: View {

    @Environment(DisplayCenter.self) private var center
    @Binding var showingSaveSheet: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.t("profiles"))
                    .font(.subheadline.weight(.medium))
                Spacer()
                if otherCount > 0 {
                    Text(L10n.t("profiles.otherLayouts", otherCount))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                // Labels the switch column; without it the toggle on each row has
                // no visible meaning.
                if !matching.isEmpty {
                    Text(L10n.t("profiles.autoColumn"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if matching.isEmpty {
                Text(L10n.t("profiles.none"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(matching) { profile in
                    row(profile)
                }
            }

            Button {
                showingSaveSheet = true
            } label: {
                Label(L10n.t("profiles.saveCurrent"), systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(center.screens.isEmpty || center.isApplying)
        }
    }

    private func row(_ profile: Profile) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(summary(profile))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(L10n.t("profiles.apply")) {
                Task { await center.apply(profile) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .disabled(center.isApplying)

            Button(role: .destructive) {
                center.profiles.remove(profile)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(L10n.t("profiles.delete"))

            Toggle("", isOn: Binding(
                get: { profile.autoApply },
                set: { newValue in
                    var copy = profile
                    copy.autoApply = newValue
                    center.profiles.update(copy)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(L10n.t("profiles.autoApply.help"))
        }
        .padding(.vertical, 2)
    }

    private func summary(_ profile: Profile) -> String {
        let modes = profile.entries.map { entry in
            "\(entry.mode.width)×\(entry.mode.height) \(entry.mode.refreshRate)Hz"
        }
        var text = modes.joined(separator: ", ")
        if profile.restoresBrightness { text += L10n.t("profiles.summary.brightness") }
        return text
    }

    private var matching: [Profile] {
        center.profiles.profiles(for: center.setKey)
    }

    private var otherCount: Int {
        center.profiles.profiles.count - matching.count
    }
}
