import SwiftUI
import KalfaUI

/// The DPI half's state at a glance: whether it is running and why, the three
/// modes, and the two actions that are about "right now" rather than about
/// configuration. Sits above the settings on the network page.
struct MenuPanel: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var supervisor: Supervisor

    var body: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.s) {
            HStack(spacing: KalfaDesign.m) {
                Image(systemName: supervisor.isActive ? "lock.shield.fill" : "lock.shield")
                    .font(KalfaDesign.titleFont)
                    .foregroundStyle(supervisor.isActive ? AnyShapeStyle(KalfaTone.accent.color) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(supervisor.isActive ? L10n.t("dpi.panel.on") : L10n.t("dpi.panel.off"))
                        .font(KalfaDesign.headingFont)
                    Text(statusReason)
                        .font(KalfaDesign.captionFont)
                        .foregroundStyle(supervisor.lastError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(KalfaTone.warn.color))
                        .lineLimit(2)
                }
                Spacer(minLength: KalfaDesign.s)
                modePicker
            }

            HStack(spacing: KalfaDesign.s) {
                // Tools like Discord's updater read the proxy environment only
                // at launch; this restarts one of them with it in place.
                Menu(L10n.t("dpi.panel.relaunch-with-kalfa")) {
                    ForEach(supervisor.ruleAppBundleIDs, id: \.self) { bundleID in
                        Button(appName(bundleID)) {
                            Task { await supervisor.relaunchWithProxy(bundleID: bundleID) }
                        }
                    }
                    if !supervisor.ruleAppBundleIDs.isEmpty { Divider() }
                    Button(L10n.t("dpi.panel.choose-another-app")) { pickAndRelaunch() }
                }
                .fixedSize()
                .help(L10n.t("dpi.panel.some-apps-read-network"))

                Spacer()

                if supervisor.isActive {
                    Button(L10n.t("dpi.panel.turn-off-now"), role: .destructive) { supervisor.panic() }
                }
            }
        }
        .padding(KalfaDesign.m)
        .kalfaGroup()
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
        .fixedSize()
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
}
