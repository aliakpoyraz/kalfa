import Foundation

/// AppConfig -> spoofdpi TOML. Dosya her motor başlatmada yeniden üretilir,
/// elle düzenlenmesi anlamsızdır; tek doğru kaynak config.json.
enum TOMLGenerator {
    static func build(from config: AppConfig) -> String {
        var out = """
        # Bu dosyayı Kalfa üretir. Elle yaptığın değişiklikler motor her
        # başladığında silinir; ayarları uygulama arayüzünden değiştir.

        [dns]
        # Hiçbir kurala uymayan alan adları sistem çözücüsüyle çözülür.
        mode = "system"

        """

        for group in config.groups where group.enabled && !group.expandedDomains.isEmpty {
            let domains = group.expandedDomains.map { "\"\($0)\"" }.joined(separator: ", ")
            out += """

            [[rules]]
            name = "\(escape(group.name))"
            priority = \(group.priority)
            match = { domains = [\(domains)] }
            dns = { mode = "\(group.dnsMode.rawValue)" }
            https = { skip = false, split-mode = "\(group.splitMode.rawValue)"\(chunkClause(group)) }

            """
        }

        // Kalan her şey dokunulmadan geçsin. Bu kural olmazsa parçalama tüm
        // trafiğe uygulanır ve ödeme sayfaları gibi hassas TLS akışları bozulur.
        out += """

        [[rules]]
        name = "diger-her-sey-dokunulmadan"
        priority = 1
        match = { domains = ["*"] }
        https = { skip = true }

        """
        return out
    }

    private static func chunkClause(_ group: DomainGroup) -> String {
        group.splitMode == .chunk ? ", chunk-size = \(group.chunkSize)" : ""
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "'")
    }
}
