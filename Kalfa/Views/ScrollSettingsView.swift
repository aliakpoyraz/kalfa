import SwiftUI
import KalfaUI

/// The smooth scrolling section of the settings popover. One switch: the values
/// behind it are fixed, because a scroll feel is judged by hand, not by number.
struct ScrollSettingsView: View {

    @Environment(ScrollService.self) private var scroll

    var body: some View {
        @Bindable var scroll = scroll

        VStack(alignment: .leading, spacing: 10) {
            Toggle(L10n.t("scroll.enable"), isOn: $scroll.isEnabled)
            helpText(L10n.t("scroll.enable.help"))

            if scroll.isEnabled && !scroll.isTrusted {
                permissionNotice
            }
        }
    }

    /// Accessibility is granted to the signature, not the app bundle, so an
    /// ad-hoc build loses it on every rebuild — worth saying out loud here.
    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("scroll.permission.title"))
                .font(.caption.weight(.semibold))
            Text(L10n.t("scroll.permission.body"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L10n.t("scroll.permission.grant")) { scroll.requestPermission() }
                Button(L10n.t("scroll.permission.open")) { scroll.openAccessibilitySettings() }
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func helpText(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
