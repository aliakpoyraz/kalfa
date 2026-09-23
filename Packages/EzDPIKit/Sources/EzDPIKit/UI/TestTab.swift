import SwiftUI
import KalfaUI

/// Test sekmesi. Sonuçlar teknik kod değil, cümle olarak sunulur:
/// "engelli ama Kalfa ile açılıyor" gibi.
struct TestTab: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var supervisor: Supervisor
    @EnvironmentObject var diagnostics: Diagnostics

    private var domains: [String] {
        store.config.groups.filter(\.enabled).flatMap(\.domains)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(diagnostics.running
                       ? L10n.t("dpi.test.testing")
                       : L10n.t("dpi.test.test-sites")) {
                    diagnostics.run(domains: domains,
                                    host: store.config.settings.listenHost,
                                    port: supervisor.activePort ?? store.config.settings.listenPort,
                                    proxyLive: supervisor.isActive)
                }
                .disabled(diagnostics.running || domains.isEmpty)
                .buttonStyle(.borderedProminent)

                if !supervisor.isActive {
                    Text(L10n.t("dpi.test.kalfa-off-only-normal"))
                        .font(.caption).foregroundStyle(.orange)
                }
                Spacer()
            }

            if diagnostics.checks.isEmpty {
                ContentUnavailableView(
                    L10n.t("dpi.test.no-test-yet"),
                    systemImage: "checkmark.seal",
                    description: Text(L10n.t("dpi.test.each-address-tried-normally"))
                )
            } else {
                List(diagnostics.checks) { check in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(for: check))
                            .foregroundStyle(color(for: check))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.domain).font(.system(size: 13, weight: .medium))
                            Text(verdict(for: check))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(4)
    }

    /// Dört olası durumun her biri için tek cümlelik karar.
    private func verdict(for check: DomainCheck) -> String {
        let direct = check.direct
        let proxied = check.throughProxy

        guard let direct else { return L10n.t("dpi.test.waiting") }

        if direct.ok && proxied == nil {
            return L10n.t("dpi.test.already-works-kalfa-not")
        }
        if !direct.ok && proxied == nil {
            return L10n.t("dpi.test.blocked-turn-kalfa-on", "\(direct.detail)")
        }
        guard let proxied else { return L10n.t("dpi.test.waiting-2") }

        if proxied.ok && !direct.ok {
            return L10n.t("dpi.test.blocked-but-kalfa-opens")
        }
        if proxied.ok && direct.ok {
            return L10n.t("dpi.test.works-either-way")
        }
        return L10n.t("dpi.test.still-blocked-with-kalfa", "\(proxied.detail)")
    }

    private func icon(for check: DomainCheck) -> String {
        guard let direct = check.direct else { return "clock" }
        if let proxied = check.throughProxy {
            if proxied.ok { return direct.ok ? "checkmark.circle.fill" : "lock.shield.fill" }
            return "xmark.circle.fill"
        }
        return direct.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private func color(for check: DomainCheck) -> Color {
        guard let direct = check.direct else { return .secondary }
        if let proxied = check.throughProxy {
            return proxied.ok ? .green : .red
        }
        return direct.ok ? .green : .orange
    }
}
