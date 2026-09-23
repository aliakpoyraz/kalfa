import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var l10n: L10n

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label(T("Genel", "General"), systemImage: "gearshape") }
            SitesTab()
                .tabItem { Label(T("Siteler", "Sites"), systemImage: "globe") }
            WhenTab()
                .tabItem { Label(T("Ne zaman", "When"), systemImage: "clock") }
            TestTab()
                .tabItem { Label(T("Test", "Test"), systemImage: "checkmark.seal") }
            LogTab()
                .tabItem { Label(T("Kayıtlar", "Log"), systemImage: "doc.plaintext") }
        }
        .padding(12)
    }
}

struct GeneralTab: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var supervisor: Supervisor
    @EnvironmentObject var l10n: L10n

    var body: some View {
        Form {
            Section {
                Picker(T("Dil", "Language"), selection: Binding(
                    get: { store.config.settings.language },
                    set: { newValue in
                        store.config.settings.language = newValue
                        l10n.language = newValue
                    }
                )) {
                    Text(T("Sistem dili", "System language")).tag(Language.system)
                    Text("Türkçe").tag(Language.tr)
                    Text("English").tag(Language.en)
                }
                // "Girişte başlat" burada değil, Kalfa'nın kendi ayarlarında:
                // ikisi de aynı SMAppService kaydını sürüyor, iki anahtar olsaydı
                // biri diğerinin durumunu göstermeden değiştirirdi.
            }

            Section {
                Toggle(T("Bazı uygulamalar için ek destek",
                         "Extra support for some apps"),
                       isOn: Binding(
                        get: { store.config.settings.manageProxyEnvVars },
                        set: { newValue in
                            store.config.settings.manageProxyEnvVars = newValue
                            // Anahtar açıldığında motorun yeniden başlaması şart;
                            // aksi halde ortam değişkeni hiç kurulmuyordu.
                            supervisor.applyConfigChange()
                        }
                       ))
                Text(T("Discord güncelleyicisi gibi birkaç uygulama bilgisayarın ağ ayarını okumaz. Bu seçenek onlara ayrıca haber verir. Sorun yaşamıyorsan kapalı bırak.",
                       "A few apps, like the Discord updater, ignore the system network settings. This option tells them separately. Leave it off unless you have trouble."))
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text(T("Uyumluluk", "Compatibility"))
            }

            Section {
                Toggle(T("Gelişmiş ayarları göster", "Show advanced settings"),
                       isOn: $store.config.settings.advancedMode)
                if store.config.settings.advancedMode {
                    Toggle(T("Port doluysa otomatik değiştir", "Switch port automatically if busy"),
                           isOn: $store.config.settings.autoPort)
                    HStack {
                        Text(T("Port", "Port"))
                        Spacer()
                        TextField("", value: Binding(
                            get: { store.config.settings.listenPort },
                            set: { store.config.settings.listenPort = Supervisor.sanitizePort($0) }
                        ), format: .number)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                    }
                    Text(T("Varsayılan 18080. 8080 gibi yaygın portlar başka programlarla çakışır.",
                           "Default is 18080. Common ports like 8080 clash with other programs."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(T("Uygula", "Apply")) { supervisor.applyConfigChange() }
                }
            } header: {
                Text(T("Gelişmiş", "Advanced"))
            }

            Section {
                if supervisor.activeServices.isEmpty {
                    Text(T("Bağlı ağ bulunamadı.", "No active network found."))
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text(T("Bağlı ağ: ", "Connected via: ") + supervisor.activeServices.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(T("Wi-Fi'dan kabloya geçtiğinde ayar kendiliğinden taşınır.",
                       "Settings follow you when you switch from Wi-Fi to cable."))
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text(T("Durum", "Status"))
            }
        }
        .formStyle(.grouped)
    }
}
