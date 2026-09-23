import SwiftUI

/// Kalfa panelinin DPI sekmesi. Teknik terim yok: kullanıcı ne olduğunu tek
/// bakışta anlamalı ve engelli bir siteyi buradan ekleyebilmeli.
///
/// Kendi çıkış düğmesi ve markası yok — ikisi de panelin altbilgisinde, bir kez.
struct MenuPanel: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var supervisor: Supervisor
    @EnvironmentObject var l10n: L10n
    @Environment(\.openSettings) private var openSettings
    @State private var quickDomain = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusCard
            modePicker
            Divider()
            sites
            relaunchRow
            Divider()
            footer
        }
    }

    // MARK: Durum

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: supervisor.isActive ? "lock.shield.fill" : "lock.shield")
                .font(.title2)
                .foregroundStyle(supervisor.isActive ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(supervisor.isActive ? T("Açık", "On") : T("Kapalı", "Off"))
                    .font(.system(size: 15, weight: .semibold))
                Text(statusReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var statusReason: String {
        if let error = supervisor.lastError { return error }
        if supervisor.isActive {
            if supervisor.mode == .forceOn { return T("Elle açtın.", "Turned on manually.") }
            let rules = supervisor.matchedRules.joined(separator: ", ")
            return rules.isEmpty
                ? T("Çalışıyor.", "Running.")
                : T("\(rules) nedeniyle çalışıyor.", "Running because of \(rules).")
        }
        switch supervisor.mode {
        case .forceOff: return T("Elle kapattın.", "Turned off manually.")
        case .forceOn: return T("Başlatılamadı.", "Could not start.")
        case .auto: return T("Şu an gereken bir durum yok.", "Nothing needs it right now.")
        }
    }

    private var modePicker: some View {
        Picker("", selection: Binding(
            get: { supervisor.mode },
            set: { supervisor.mode = $0 }
        )) {
            Text(T("Otomatik", "Automatic")).tag(RunMode.auto)
            Text(T("Sürekli açık", "Always on")).tag(RunMode.forceOn)
            Text(T("Kapalı", "Off")).tag(RunMode.forceOff)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: Siteler

    private var sites: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(T("Siteler", "Sites"))
                .font(.caption).foregroundStyle(.secondary)

            ForEach($store.config.groups) { $group in
                Toggle(isOn: Binding(
                    get: { group.enabled },
                    set: { newValue in
                        group.enabled = newValue
                        supervisor.applyConfigChange()
                    }
                )) {
                    Text("\(group.name) · \(group.domains.count)")
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
            }

            HStack(spacing: 6) {
                TextField(T("engellenen-site.com", "blocked-site.com"), text: $quickDomain)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit(addQuickDomain)
                Button(T("Ekle", "Add"), action: addQuickDomain)
                    .disabled(quickDomain.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// Menüden eklenen adresler "Benim sitelerim" grubuna gider; kullanıcı
    /// grup kavramıyla uğraşmadan engelli bir siteyi hemen ekleyebilsin.
    private func addQuickDomain() {
        let raw = quickDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty else { return }
        let cleaned = raw
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .split(separator: "/").first.map(String.init) ?? raw

        let name = T("Benim sitelerim", "My sites")
        if let index = store.config.groups.firstIndex(where: { $0.name == name }) {
            if !store.config.groups[index].domains.contains(cleaned) {
                store.config.groups[index].domains.append(cleaned)
            }
        } else {
            var group = DomainGroup(name: name, domains: [cleaned],
                                    priority: (store.config.groups.map(\.priority).max() ?? 10) + 10)
            group.apply(preset: .standard)
            store.config.groups.append(group)
        }
        quickDomain = ""
        supervisor.applyConfigChange()
    }

    // MARK: Alt bölüm

    /// Discord güncelleyicisi gibi araçlar ortam değişkenini yalnızca başlarken
    /// okur. Uygulama zaten açıkken DPI devreye girdiğinde onlar korumasız
    /// kalır; bu düğme uygulamayı Kalfa ortamıyla yeniden başlatır.
    @ViewBuilder
    private var relaunchRow: some View {
        Divider()
        VStack(alignment: .leading, spacing: 6) {
            Text(T("Uygulama güncellenemiyorsa", "If an app cannot update"))
                .font(.caption).foregroundStyle(.secondary)
            Menu(T("Kalfa ile yeniden başlat", "Relaunch with Kalfa")) {
                ForEach(supervisor.ruleAppBundleIDs, id: \.self) { bundleID in
                    Button(appName(bundleID)) {
                        Task { await supervisor.relaunchWithProxy(bundleID: bundleID) }
                    }
                }
                if !supervisor.ruleAppBundleIDs.isEmpty { Divider() }
                Button(T("Başka uygulama seç…", "Choose another app…")) { pickAndRelaunch() }
            }
            .menuStyle(.borderlessButton)
            Text(T("Bazı uygulamalar ağ ayarını yalnızca açılışta okur. Bu, uygulamayı Kalfa ortamıyla yeniden başlatır.",
                   "Some apps read network settings only at launch. This restarts the app inside Kalfa's environment."))
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Kurallarda olmayan herhangi bir uygulama da seçilebilir.
    private func pickAndRelaunch() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        Task { await supervisor.relaunchWithProxy(bundleID: bundleID) }
    }

    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private var footer: some View {
        HStack {
            Button(T("DPI ayarları…", "DPI settings…")) {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            Spacer()
            if supervisor.isActive {
                Button(T("Hemen kapat", "Turn off now")) { supervisor.panic() }
                    .tint(.red)
            }
        }
    }
}
