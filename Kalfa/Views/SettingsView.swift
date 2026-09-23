import SwiftUI

struct SettingsView: View {

    @Environment(DisplayCenter.self) private var center
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        @Bindable var settings = center.settings

        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("settings.title"))
                .font(.headline)

            Picker(L10n.t("language"), selection: $settings.language) {
                ForEach(L10n.Language.allCases) { language in
                    Text(language.nativeName).tag(language)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            Divider()

            Toggle(L10n.t("settings.autoApply"), isOn: $settings.autoApplyProfiles)
            Toggle(L10n.t("settings.persist"), isOn: $settings.persistModeChanges)
            helpText(L10n.t("settings.persist.help"))

            Divider()

            Toggle(L10n.t("settings.showLowRes"), isOn: $settings.showLowResolutionTwins)
            Toggle(L10n.t("settings.showHidden"), isOn: $settings.showHiddenModes)
            helpText(L10n.t("settings.showHidden.help"))

            Divider()

            ScrollSettingsView()

            Divider()

            Toggle(L10n.t("settings.launchAtLogin"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    // macOS refuses registration while the user has the item
                    // disabled in System Settings; only they can undo that.
                    if !LaunchAtLogin.set(newValue) {
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                }
        }
        .toggleStyle(.checkbox)
        .font(.callout)
        .padding(18)
        .frame(width: 360, alignment: .leading)
    }

    private func helpText(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
