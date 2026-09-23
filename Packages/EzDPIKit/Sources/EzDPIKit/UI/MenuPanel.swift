import SwiftUI
import KalfaUI

/// Kalfa panelinin DPI sekmesi. Teknik terim yok: kullanıcı ne olduğunu tek
/// bakışta anlamalı ve engelli bir siteyi buradan ekleyebilmeli.
///
/// Kendi çıkış düğmesi ve markası yok — ikisi de panelin altbilgisinde, bir kez.
struct MenuPanel: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var supervisor: Supervisor
    @State private var quickDomain = ""

    var body: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.s) {
            statusCard
            modePicker
            sites
            relaunchRow
            footer
        }
    }

    // MARK: Durum

    /// Same shape as a tile elsewhere in the panel: an icon that carries the
    /// state in its tint, a line saying what is true, and a line saying why.
    private var statusCard: some View {
        HStack(alignment: .top, spacing: KalfaDesign.s) {
            Image(systemName: supervisor.isActive ? "lock.shield.fill" : "lock.shield")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(supervisor.isActive ? KalfaRole.dpi.tint : Color.secondary)
                .frame(width: 28, height: 28)
                .background(
                    (supervisor.isActive ? KalfaRole.dpi.tint : Color.secondary)
                        .opacity(supervisor.isActive ? 0.18 : 0.10),
                    in: RoundedRectangle(cornerRadius: KalfaDesign.controlRadius, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(supervisor.isActive ? L10n.t("dpi.panel.on") : L10n.t("dpi.panel.off"))
                    .font(KalfaDesign.bodyFont.weight(.medium))
                Text(statusReason)
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(supervisor.lastError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(KalfaDesign.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kalfaSurface(tint: KalfaRole.dpi.tint, isActive: supervisor.isActive, radius: KalfaDesign.tileRadius)
    }

    private var statusReason: String {
        if let error = supervisor.lastError { return error }
        if supervisor.isActive {
            if supervisor.mode == .forceOn { return L10n.t("dpi.panel.turned-on-manually") }
            let rules = supervisor.matchedRules.joined(separator: ", ")
            return rules.isEmpty
                ? L10n.t("dpi.panel.running")
                : L10n.t("dpi.panel.running-because", "\(rules)")
        }
        switch supervisor.mode {
        case .forceOff: return L10n.t("dpi.panel.turned-off-manually")
        case .forceOn: return L10n.t("dpi.panel.could-not-start")
        case .auto: return L10n.t("dpi.panel.nothing-needs-right-now")
        }
    }

    private var modePicker: some View {
        Picker("", selection: Binding(
            get: { supervisor.mode },
            set: { supervisor.mode = $0 }
        )) {
            Text(L10n.t("dpi.panel.automatic")).tag(RunMode.auto)
            Text(L10n.t("dpi.panel.always-on")).tag(RunMode.forceOn)
            Text(L10n.t("dpi.panel.off")).tag(RunMode.forceOff)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: Siteler

    private var sites: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.xs) {
            Text(L10n.t("dpi.panel.sites"))
                .font(KalfaDesign.captionFont).foregroundStyle(.secondary)

            ForEach($store.config.groups) { $group in
                Toggle(isOn: Binding(
                    get: { group.enabled },
                    set: { newValue in
                        group.enabled = newValue
                        supervisor.applyConfigChange()
                    }
                )) {
                    Text("\(group.name) · \(group.domains.count)")
                        .font(KalfaDesign.bodyFont)
                }
                .toggleStyle(.checkbox)
            }

            HStack(spacing: KalfaDesign.xs) {
                TextField(L10n.t("dpi.panel.blocked-site-com"), text: $quickDomain)
                    .textFieldStyle(.roundedBorder)
                    .font(KalfaDesign.bodyFont)
                    .onSubmit(addQuickDomain)
                Button(L10n.t("dpi.panel.add"), action: addQuickDomain)
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

        let name = L10n.t("dpi.panel.my-sites")
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
        Divider().opacity(0.5)
        VStack(alignment: .leading, spacing: KalfaDesign.xs) {
            Text(L10n.t("dpi.panel.if-app-cannot-update"))
                .font(KalfaDesign.captionFont).foregroundStyle(.secondary)
            Menu(L10n.t("dpi.panel.relaunch-with-kalfa")) {
                ForEach(supervisor.ruleAppBundleIDs, id: \.self) { bundleID in
                    Button(appName(bundleID)) {
                        Task { await supervisor.relaunchWithProxy(bundleID: bundleID) }
                    }
                }
                if !supervisor.ruleAppBundleIDs.isEmpty { Divider() }
                Button(L10n.t("dpi.panel.choose-another-app")) { pickAndRelaunch() }
            }
            .menuStyle(.borderlessButton)
            Text(L10n.t("dpi.panel.some-apps-read-network"))
                .font(KalfaDesign.captionFont).foregroundStyle(.tertiary)
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
            Button(L10n.t("dpi.panel.dpi-settings")) { EzDPI.showSettings?() }
                .buttonStyle(.borderless)
                .font(KalfaDesign.captionFont)
            Spacer()
            if supervisor.isActive {
                Button(L10n.t("dpi.panel.turn-off-now")) { supervisor.panic() }
                    .buttonStyle(.borderless)
                    .font(KalfaDesign.captionFont)
                    .tint(.red)
            }
        }
    }
}
