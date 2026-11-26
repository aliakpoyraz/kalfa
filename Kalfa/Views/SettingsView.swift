import EzDPIKit
import SwiftUI
import KalfaUI

/// Kalfa's own preferences, its shortcuts, and what it is.
struct SettingsView: View {

    private static let repositoryURL = URL(string: "https://github.com/aliakpoyraz/kalfa")!

    @Environment(DisplayCenter.self) private var center
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        @Bindable var settings = center.settings

        Form {
            Section {
                Picker(L10n.t("language"), selection: $settings.language) {
                    ForEach(L10n.Language.allCases) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
                Toggle(L10n.t("settings.launchAtLogin"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        // macOS refuses registration while the user has the item
                        // disabled in System Settings; only they can undo that.
                        if !LaunchAtLogin.set(newValue) {
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
            }

            Section {
                Toggle(L10n.t("settings.autoApply"), isOn: $settings.autoApplyProfiles)
                Toggle(isOn: $settings.persistModeChanges) {
                    Text(L10n.t("settings.persist"))
                    Text(L10n.t("settings.persist.help"))
                }
                Toggle(L10n.t("settings.showLowRes"), isOn: $settings.showLowResolutionTwins)
                Toggle(isOn: $settings.showHiddenModes) {
                    Text(L10n.t("settings.showHidden"))
                    Text(L10n.t("settings.showHidden.help"))
                }
            } header: {
                Text(L10n.t("tab.display"))
            }

            Section {
                HotkeysView()
            } header: {
                Text(L10n.t("hotkeys"))
            } footer: {
                Text(L10n.t("hotkey.help")).kalfaFootnote()
            }

            Section(L10n.t("window.section.about")) {
                HStack(spacing: KalfaDesign.m) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("app.name"))
                            .font(KalfaDesign.titleFont)
                        Text(L10n.t("about.tagline")).kalfaFootnote()
                    }
                    Spacer()
                    Text(L10n.t("about.version", shortVersion, buildNumber))
                        .font(KalfaDesign.captionFont.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(L10n.t("about.credits")).kalfaFootnote()
                LabeledContent(L10n.t("about.license")) {
                    Link(L10n.t("about.repository"), destination: Self.repositoryURL)
                }
                // What used to be the DPI half's own About tab. Two screens
                // saying the version and the licence was one screen too many.
                LabeledContent {
                    Text(L10n.t("about.engine.value"))
                } label: {
                    Text(L10n.t("about.engine"))
                    Text(L10n.t("about.engine.listening", EzDPI.engineSummary))
                }
                LabeledContent(L10n.t("about.files")) {
                    Button(L10n.t("about.files.config")) { EzDPI.revealConfigFolder() }
                    Button(L10n.t("about.files.log")) { EzDPI.revealLogFolder() }
                }
                Text(L10n.t("about.copyright")).kalfaFootnote()
            }
        }
        .kalfaForm()
    }

    private var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
