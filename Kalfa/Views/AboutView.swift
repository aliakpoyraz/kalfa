import EzDPIKit
import SwiftUI
import KalfaUI

struct AboutView: View {

    private static let repositoryURL = URL(string: "https://github.com/aliakpoyraz/kalfa")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let icon = NSImage(named: "AppIcon") {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 52, height: 52)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("app.name"))
                        .font(.title3.weight(.semibold))
                    Text(L10n.t("about.tagline"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(L10n.t("about.version", shortVersion, buildNumber))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            Text(L10n.t("about.credits"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Link(L10n.t("about.repository"), destination: Self.repositoryURL)
                    .font(.caption)
                Text(L10n.t("about.license"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Divider()

            // What used to be the DPI half's own About tab. Two screens saying
            // the version and the licence was one screen too many.
            HStack(spacing: 6) {
                Text(L10n.t("about.engine"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L10n.t("about.engine.value"))
                    .font(.caption.weight(.medium))
                Spacer()
            }
            Text(L10n.t("about.engine.listening", EzDPI.engineSummary))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)

            HStack(spacing: 10) {
                Button(L10n.t("about.files.config")) { EzDPI.revealConfigFolder() }
                Button(L10n.t("about.files.log")) { EzDPI.revealLogFolder() }
                Spacer()
            }
            .controlSize(.small)

            Text(L10n.t("about.copyright"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(maxWidth: 420, alignment: .leading)
    }

    private var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
