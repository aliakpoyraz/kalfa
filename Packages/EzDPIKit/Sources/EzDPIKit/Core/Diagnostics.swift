import Foundation

struct DomainCheck: Identifiable {
    let id = UUID()
    let domain: String
    var throughProxy: CheckResult?
    var direct: CheckResult?
}

struct CheckResult {
    let ok: Bool
    let detail: String
}

/// Alan alan test. Geçen sefer elle yapılan "curl -x ile dene, logu oku"
/// döngüsünün otomatik hâli: hangi alan proxy üzerinden geçiyor, hangisi
/// doğrudan gidince engelleniyor, tek tabloda görünür.
@MainActor
final class Diagnostics: ObservableObject {
    @Published private(set) var checks: [DomainCheck] = []
    @Published private(set) var running = false

    func run(domains: [String], host: String, port: Int, proxyLive: Bool) {
        guard !running else { return }
        running = true
        checks = domains.map { DomainCheck(domain: $0) }

        Task.detached(priority: .userInitiated) {
            for (index, domain) in domains.enumerated() {
                let direct = Self.probe(domain: domain, proxy: nil)
                let proxied = proxyLive ? Self.probe(domain: domain, proxy: "http://\(host):\(port)") : nil
                await MainActor.run {
                    guard index < self.checks.count else { return }
                    self.checks[index].direct = direct
                    self.checks[index].throughProxy = proxied
                }
            }
            await MainActor.run { self.running = false }
        }
    }

    /// curl çıkış kodlarını okunur Türkçeye çevirir. Sertifika hataları
    /// Türkiye'de TLS araya girme (MITM) belirtisidir, ayrıca vurgulanır.
    nonisolated static func probe(domain: String, proxy: String?) -> CheckResult {
        var args = ["-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "8"]
        if let proxy {
            args += ["-x", proxy]
        } else {
            args += ["--noproxy", "*"]
        }
        args.append("https://\(domain)")

        let result = Shell.run("/usr/bin/curl", args, timeout: 12)
        if result.ok {
            let code = result.stdout.trimmingCharacters(in: .whitespaces)
            return CheckResult(ok: true, detail: "HTTP \(code)")
        }
        return CheckResult(ok: false, detail: explain(result.status))
    }

    nonisolated static func explain(_ code: Int32) -> String {
        switch code {
        case 6: return "Alan adı çözülemedi (DNS engeli olabilir)"
        case 7: return "Bağlanılamadı"
        case 28: return "Zaman aşımı (DPI düşürüyor olabilir)"
        case 35: return "TLS el sıkışması başarısız (DPI)"
        case 60: return "Sertifika güvenilmez (araya girme belirtisi)"
        case -2: return "Zaman aşımı"
        default: return "curl hata \(code)"
        }
    }
}
