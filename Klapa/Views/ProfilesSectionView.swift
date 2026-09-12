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
                Text("Profiller")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if otherCount > 0 {
                    Text("\(otherCount) tanesi başka dizilim için")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if matching.isEmpty {
                Text("Bu dizilim için kayıtlı profil yok.")
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
                Label("Şu anki durumu kaydet", systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(center.screens.isEmpty || center.isApplying)
        }
    }

    private func row(_ profile: Profile) -> some View {
        HStack(spacing: 6) {
            Button {
                var copy = profile
                copy.autoApply.toggle()
                center.profiles.update(copy)
            } label: {
                Image(systemName: profile.autoApply ? "bolt.fill" : "bolt")
                    .foregroundStyle(profile.autoApply ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help(profile.autoApply
                  ? "Bu dizilim bağlandığında kendiliğinden uygulanır"
                  : "Kendiliğinden uygulanmaz")

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(summary(profile))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Uygula") {
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
            .help("Profili sil")
        }
        .padding(.vertical, 2)
    }

    private func summary(_ profile: Profile) -> String {
        let modes = profile.entries.map { entry in
            "\(entry.mode.width)×\(entry.mode.height) \(entry.mode.refreshRate)Hz"
        }
        var text = modes.joined(separator: ", ")
        if profile.restoresBrightness { text += " · parlaklık" }
        return text
    }

    private var matching: [Profile] {
        center.profiles.profiles(for: center.setKey)
    }

    private var otherCount: Int {
        center.profiles.profiles.count - matching.count
    }
}
