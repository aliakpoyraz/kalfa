import SwiftUI
import KalfaUI

/// The smooth scrolling section of the settings popover. One switch: the values
/// behind it are fixed, because a scroll feel is judged by hand, not by number.
struct ScrollSettingsView: View {

    @Environment(ScrollService.self) private var scroll

    var body: some View {
        @Bindable var scroll = scroll

        Toggle(isOn: $scroll.isEnabled) {
            Text(L10n.t("scroll.enable"))
            Text(L10n.t("scroll.enable.help"))
        }

        if scroll.isEnabled && !scroll.isTrusted {
            permissionNotice
        }
    }

    /// Accessibility is granted to the signature, not the app bundle, so an
    /// ad-hoc build loses it on every rebuild — worth saying out loud here.
    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.s) {
            Label(L10n.t("scroll.permission.title"), systemImage: "exclamationmark.triangle.fill")
                .font(KalfaDesign.headingFont)
                .foregroundStyle(KalfaTone.warn.color)
            Text(L10n.t("scroll.permission.body")).kalfaFootnote()
            HStack {
                Button(L10n.t("scroll.permission.grant")) { scroll.requestPermission() }
                Button(L10n.t("scroll.permission.open")) { scroll.openAccessibilitySettings() }
            }
        }
    }
}
