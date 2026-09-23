import SwiftUI
import KalfaUI

/// The DPI page of the Kalfa window.
///
/// A segmented control rather than tabs. It sits inside the window's sidebar,
/// and tabs within a sidebar selection is two navigation systems stacked on top
/// of each other — the upkeep page next door made the same choice.
struct SettingsView: View {

    private enum Page: String, CaseIterable, Identifiable {
        case sites, when, test, log, general
        var id: String { rawValue }
        var title: String { L10n.t("dpi.page.\(rawValue)") }
    }

    @State private var page: Page = .sites

    var body: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.m) {
            Picker("", selection: $page) {
                ForEach(Page.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch page {
            case .sites: SitesTab()
            case .when: WhenTab()
            case .test: TestTab()
            case .log: LogTab()
            case .general: GeneralTab()
            }
        }
    }
}

struct GeneralTab: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var supervisor: Supervisor

    var body: some View {
        Form {
            Section {
                Toggle(L10n.t("dpi.settings.extra-support-some-apps"),
                       isOn: Binding(
                        get: { store.config.settings.manageProxyEnvVars },
                        set: { newValue in
                            store.config.settings.manageProxyEnvVars = newValue
                            // Anahtar açıldığında motorun yeniden başlaması şart;
                            // aksi halde ortam değişkeni hiç kurulmuyordu.
                            supervisor.applyConfigChange()
                        }
                       ))
                Text(L10n.t("dpi.settings.few-apps-like-discord"))
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text(L10n.t("dpi.settings.compatibility"))
            }

            Section {
                Toggle(L10n.t("dpi.settings.show-advanced-settings"),
                       isOn: $store.config.settings.advancedMode)
                if store.config.settings.advancedMode {
                    Toggle(L10n.t("dpi.settings.switch-port-automatically-if"),
                           isOn: $store.config.settings.autoPort)
                    HStack {
                        Text(L10n.t("dpi.settings.port"))
                        Spacer()
                        TextField("", value: Binding(
                            get: { store.config.settings.listenPort },
                            set: { store.config.settings.listenPort = Supervisor.sanitizePort($0) }
                        ), format: .number)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                    }
                    Text(L10n.t("dpi.settings.default-18080-common-ports"))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(L10n.t("dpi.settings.apply")) { supervisor.applyConfigChange() }
                }
            } header: {
                Text(L10n.t("dpi.settings.advanced"))
            }

            Section {
                if supervisor.activeServices.isEmpty {
                    Text(L10n.t("dpi.settings.no-active-network-found"))
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text(L10n.t("dpi.settings.connected-via", supervisor.activeServices.joined(separator: ", ")))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(L10n.t("dpi.settings.settings-follow-when-switch"))
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text(L10n.t("dpi.settings.status"))
            }
        }
        .formStyle(.grouped)
    }
}
