import SwiftUI

/// Test sekmesi. Sonuçlar teknik kod değil, cümle olarak sunulur:
/// "engelli ama Kalfa ile açılıyor" gibi.
struct TestTab: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var supervisor: Supervisor
    @EnvironmentObject var diagnostics: Diagnostics
    @EnvironmentObject var l10n: L10n

    private var domains: [String] {
        store.config.groups.filter(\.enabled).flatMap(\.domains)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(diagnostics.running
                       ? T("Test sürüyor…", "Testing…")
                       : T("Siteleri test et", "Test sites")) {
                    diagnostics.run(domains: domains,
                                    host: store.config.settings.listenHost,
                                    port: supervisor.activePort ?? store.config.settings.listenPort,
                                    proxyLive: supervisor.isActive)
                }
                .disabled(diagnostics.running || domains.isEmpty)
                .buttonStyle(.borderedProminent)

                if !supervisor.isActive {
                    Text(T("Kalfa kapalı, yalnızca normal bağlantı denenecek.",
                           "Kalfa is off, only the normal connection will be tested."))
                        .font(.caption).foregroundStyle(.orange)
                }
                Spacer()
            }

            if diagnostics.checks.isEmpty {
                ContentUnavailableView(
                    T("Henüz test yapılmadı", "No test yet"),
                    systemImage: "checkmark.seal",
                    description: Text(T("Listendeki her adres önce normal, sonra Kalfa üzerinden denenir.",
                                        "Each address is tried normally first, then through Kalfa."))
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

        guard let direct else { return T("Bekleniyor…", "Waiting…") }

        if direct.ok && proxied == nil {
            return T("Zaten açılıyor, Kalfa gerekmiyor.", "Already works, Kalfa not needed.")
        }
        if !direct.ok && proxied == nil {
            return T("Açılmıyor (\(direct.detail)). Kalfa'yı açıp tekrar test et.",
                     "Blocked (\(direct.detail)). Turn Kalfa on and test again.")
        }
        guard let proxied else { return T("Bekleniyor…", "Waiting…") }

        if proxied.ok && !direct.ok {
            return T("Engelli ama Kalfa ile açılıyor.", "Blocked, but Kalfa opens it.")
        }
        if proxied.ok && direct.ok {
            return T("Her iki durumda da açılıyor.", "Works either way.")
        }
        return T("Kalfa ile de açılmadı (\(proxied.detail)). Siteler sekmesinden başka bir yöntem dene.",
                 "Still blocked with Kalfa (\(proxied.detail)). Try another method in the Sites tab.")
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
