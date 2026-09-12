import SwiftUI

struct SettingsView: View {

    @Environment(DisplayCenter.self) private var center
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        @Bindable var settings = center.settings

        VStack(alignment: .leading, spacing: 12) {
            Text("Ayarlar")
                .font(.headline)

            Toggle("Dizilim değişince profili uygula", isOn: $settings.autoApplyProfiles)
            Toggle("Değişiklikleri kalıcı yaz", isOn: $settings.persistModeChanges)
            helpText("""
                Kapalıyken değişiklik yalnızca bu oturumda geçerli olur. Açıkken pencere \
                sunucusunun kayıtlı dizilim ayarının üzerine yazılır — kapak kapalıyken \
                hatırlanan bozuk ayarı düzeltmenin yolu budur.
                """)

            Divider()

            Toggle("Düşük çözünürlüklü eşleri göster", isOn: $settings.showLowResolutionTwins)
            Toggle("Gizli modları göster", isOn: $settings.showHiddenModes)
            helpText("Gizli modlar macOS'un \"asla gösterme\" işaretlediği zamanlamalardır; monitör kararabilir.")

            Divider()

            Toggle("Girişte başlat", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    if !LaunchAtLogin.set(newValue) {
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                }
        }
        .toggleStyle(.checkbox)
        .font(.callout)
        .padding(18)
        .frame(width: 340, alignment: .leading)
    }

    private func helpText(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
