import Foundation

/// Tek bir ağ servisinin proxy ayarının değiştirmeden önceki hâli.
struct ProxySnapshot: Codable, Equatable {
    var service: String
    var webEnabled: Bool
    var webServer: String
    var webPort: String
    var secureEnabled: Bool
    var secureServer: String
    var securePort: String
}

/// Proxy açıkken diske yazılan kirli durum. Uygulama çökerse bir sonraki
/// açılışta bu dosya bulunur ve sistem proxy'si eski hâline döndürülür.
/// Bu dosya olmasa çökme = ölü porta bakan sistem proxy'si = tamamen kesik internet.
struct DirtyState: Codable {
    var snapshots: [ProxySnapshot]
    var appliedAt: Date
    var host: String
    var port: Int
    var envVarsSet: Bool
    /// Servis başına, biz dokunmadan önceki muafiyet listesi. Eski durum
    /// dosyalarında bu anahtar yok; optional olduğu için çözümleme kırılmaz.
    var bypassBefore: [String: [String]]?
}

enum SystemProxyController {
    // MARK: Servis keşfi

    /// Etkin (IP almış) ağ servisleri. "Wi-Fi" sabit yazmak dock/ethernet'e
    /// geçince sessizce çalışmamaya yol açıyordu; bu yüzden her seferinde bakılır.
    static func activeServices() -> [String] {
        let list = Shell.networksetup(["-listallnetworkservices"])
        guard list.ok else { return [] }
        let services = list.stdout
            .split(separator: "\n")
            .dropFirst() // ilk satır açıklama metni
            .map(String.init)
            .filter { !$0.hasPrefix("*") }        // yıldızlı = devre dışı servis
            .map { $0.trimmingCharacters(in: .whitespaces) }

        return services.filter { service in
            let info = Shell.networksetup(["-getinfo", service])
            guard info.ok else { return false }
            // "IP address: 192.168.1.20" varsa bağlı; "IP address: none" ise değil.
            for line in info.stdout.split(separator: "\n") {
                if line.hasPrefix("IP address:") {
                    let value = line.replacingOccurrences(of: "IP address:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    return !value.isEmpty && value.lowercased() != "none"
                }
            }
            return false
        }
    }

    static func targetServices(config: AppSettings) -> [String] {
        config.pinnedServices.isEmpty ? activeServices() : config.pinnedServices
    }

    // MARK: Anlık durum

    static func snapshot(of service: String) -> ProxySnapshot {
        let web = parse(Shell.networksetup(["-getwebproxy", service]).stdout)
        let secure = parse(Shell.networksetup(["-getsecurewebproxy", service]).stdout)
        return ProxySnapshot(
            service: service,
            webEnabled: web.enabled, webServer: web.server, webPort: web.port,
            secureEnabled: secure.enabled, secureServer: secure.server, securePort: secure.port
        )
    }

    private static func parse(_ output: String) -> (enabled: Bool, server: String, port: String) {
        var enabled = false, server = "", port = ""
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "Enabled": enabled = parts[1].lowercased() == "yes"
            case "Server": server = parts[1]
            case "Port": port = parts[1]
            default: break
            }
        }
        return (enabled, server, port)
    }

    /// Sistem proxy'si şu an bizim porta mı bakıyor?
    static func isPointingAtUs(host: String, port: Int) -> Bool {
        activeServices().contains { service in
            let s = snapshot(of: service)
            return s.secureEnabled && s.secureServer == host && s.securePort == String(port)
        }
    }

    // MARK: Muafiyet listesi

    /// `networksetup` liste boşken açıklama cümlesi basar, alan adı değil.
    static func bypassDomains(of service: String) -> [String] {
        let out = Shell.networksetup(["-getproxybypassdomains", service])
        guard out.ok else { return [] }
        return out.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains(" ") }
    }

    private static func setBypassDomains(_ domains: [String], service: String) {
        // Boş liste için argümansız çağrı listeyi temizler.
        if domains.isEmpty {
            Shell.networksetup(["-setproxybypassdomains", service, ""])
        } else {
            Shell.networksetup(["-setproxybypassdomains", service] + domains)
        }
    }

    // MARK: Uygula / geri al

    @discardableResult
    static func enable(host: String, port: Int, services: [String], envVars: Bool,
                       bypass: [String] = []) -> Bool {
        guard !services.isEmpty else {
            Log.write(.error, "Etkin ağ servisi bulunamadı, sistem proxy'si ayarlanmadı.")
            return false
        }

        // ÖNCE kirli durumu yaz. Sıra tersine dönerse çökme anında geri alacak
        // bilgi diskte olmaz.
        let snaps = services.map { snapshot(of: $0) }
        var bypassBefore: [String: [String]] = [:]
        for service in services { bypassBefore[service] = bypassDomains(of: service) }
        writeDirtyState(DirtyState(snapshots: snaps, appliedAt: Date(),
                                   host: host, port: port, envVarsSet: envVars,
                                   bypassBefore: bypassBefore))

        var allOK = true
        for service in services {
            let a = Shell.networksetup(["-setwebproxy", service, host, String(port)])
            let b = Shell.networksetup(["-setsecurewebproxy", service, host, String(port)])
            if !a.ok || !b.ok {
                allOK = false
                Log.write(.error, "\(service): proxy ayarlanamadı — \(a.stderr) \(b.stderr)")
            }
            if !bypass.isEmpty {
                // Kullanıcının kendi eklediklerini silmeden üstüne koy.
                let merged = (bypassBefore[service] ?? []) + bypass
                var seen = Set<String>()
                setBypassDomains(merged.filter { seen.insert($0).inserted }, service: service)
            }
        }
        if allOK {
            Log.write(.info, "Sistem proxy'si açıldı (\(host):\(port)) — \(services.joined(separator: ", "))")
        }
        if !bypass.isEmpty {
            Log.write(.info, "Proxy muafiyeti: \(bypass.joined(separator: ", "))")
        }
        if envVars { setEnvVars(host: host, port: port, bypass: bypass) }
        return allOK
    }

    /// Kirli durum dosyasındaki eski ayarları geri koyar. Dosya yoksa da
    /// güvenli tarafta kalmak için etkin servislerde proxy'yi kapatır.
    static func restore(fallbackServices: [String] = []) {
        if let state = readDirtyState() {
            for snap in state.snapshots {
                apply(snap)
            }
            for (service, domains) in state.bypassBefore ?? [:] {
                setBypassDomains(domains, service: service)
            }
            if state.envVarsSet { unsetEnvVars() }
            clearDirtyState()
            Log.write(.info, "Sistem proxy'si eski hâline döndürüldü.")
            return
        }
        let services = fallbackServices.isEmpty ? activeServices() : fallbackServices
        for service in services {
            Shell.networksetup(["-setwebproxystate", service, "off"])
            Shell.networksetup(["-setsecurewebproxystate", service, "off"])
        }
        unsetEnvVars()
        if !services.isEmpty {
            Log.write(.info, "Sistem proxy'si kapatıldı — \(services.joined(separator: ", "))")
        }
    }

    private static func apply(_ snap: ProxySnapshot) {
        if snap.webEnabled, !snap.webServer.isEmpty {
            Shell.networksetup(["-setwebproxy", snap.service, snap.webServer, snap.webPort])
        } else {
            Shell.networksetup(["-setwebproxystate", snap.service, "off"])
        }
        if snap.secureEnabled, !snap.secureServer.isEmpty {
            Shell.networksetup(["-setsecurewebproxy", snap.service, snap.secureServer, snap.securePort])
        } else {
            Shell.networksetup(["-setsecurewebproxystate", snap.service, "off"])
        }
    }

    /// Açılışta çağrılır: önceki oturum çökerek kapandıysa proxy'yi kurtarır.
    static func recoverIfDirty() {
        guard readDirtyState() != nil else { return }
        Log.write(.warn, "Önceki oturum temiz kapanmamış. Sistem proxy'si geri alınıyor.")
        restore()
    }

    // MARK: Ortam değişkenleri

    /// Discord güncelleyicisi gibi sistem proxy'sini okumayan, yalnızca
    /// https_proxy ortam değişkenine bakan uygulamalar için.
    /// Motor durunca MUTLAKA temizlenir, aksi halde değişken ölü porta işaret
    /// eder ve onu okuyan her uygulamanın ağı kesilir.
    static func setEnvVars(host: String, port: Int, bypass: [String] = []) {
        let value = "http://\(host):\(port)"
        for key in ["https_proxy", "HTTPS_PROXY", "http_proxy", "HTTP_PROXY"] {
            Shell.run("/bin/launchctl", ["setenv", key, value])
        }
        // curl, Node ve Go `*.host` sözdizimini anlamaz; `.host` bekler.
        let noProxy = bypass
            .map { $0.hasPrefix("*") ? String($0.dropFirst()) : $0 }
            .joined(separator: ",")
        if !noProxy.isEmpty {
            for key in ["no_proxy", "NO_PROXY"] {
                Shell.run("/bin/launchctl", ["setenv", key, noProxy])
            }
        }
        Log.write(.info, "Ortam değişkenleri ayarlandı (\(value)).")
    }

    static func unsetEnvVars() {
        for key in ["https_proxy", "HTTPS_PROXY", "http_proxy", "HTTP_PROXY",
                    "no_proxy", "NO_PROXY"] {
            Shell.run("/bin/launchctl", ["unsetenv", key])
        }
    }

    // MARK: Kirli durum dosyası

    private static func writeDirtyState(_ state: DirtyState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: Paths.dirtyState, options: .atomic)
    }

    private static func readDirtyState() -> DirtyState? {
        guard let data = try? Data(contentsOf: Paths.dirtyState) else { return nil }
        return try? JSONDecoder().decode(DirtyState.self, from: data)
    }

    private static func clearDirtyState() {
        try? FileManager.default.removeItem(at: Paths.dirtyState)
    }
}
