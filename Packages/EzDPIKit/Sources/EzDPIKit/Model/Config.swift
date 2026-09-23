import Foundation

// MARK: - Alan adı grupları

enum SplitMode: String, Codable, CaseIterable, Identifiable {
    /// Cut the first write after N bytes.
    case chunk
    /// Cut inside the server name itself.
    case sni
    /// Re-frame the handshake as several TLS records. Survives a filter that
    /// reassembles the stream before looking, which byte splitting does not.
    case record
    /// Several cuts at unpredictable offsets.
    case random
    /// Pass through untouched.
    case none
    /// Raw-socket strategies from the days of the bundled engine. Kept so that
    /// an existing config still decodes; both now run as `record`, which is the
    /// closest thing a process without root can do.
    case disorder, fake

    var id: String { rawValue }

    /// Offered in the advanced picker. The two legacy values are not.
    static var selectable: [SplitMode] { [.chunk, .record, .sni, .random, .none] }

    var label: String {
        switch self {
        case .chunk: return "chunk (parçala)"
        case .sni: return "sni"
        case .record: return "record (TLS kaydı)"
        case .random: return "random"
        case .none: return "none (dokunma)"
        case .disorder: return "disorder (→ record)"
        case .fake: return "fake (→ record)"
        }
    }
}

enum DNSMode: String, Codable, CaseIterable, Identifiable {
    case system, https, udp
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Sistem çözücüsü"
        case .https: return "DoH (DNS over HTTPS)"
        case .udp: return "Düz UDP"
        }
    }
}

/// Son kullanıcıya gösterilen yöntem seçenekleri. Teknik karşılıkları
/// gizli; "Gelişmiş" açılınca ham değerler düzenlenebilir hâle gelir.
enum BypassPreset: String, Codable, CaseIterable, Identifiable {
    case standard, alternative1, alternative2, custom
    var id: String { rawValue }

    @MainActor var label: String {
        switch self {
        case .standard: return T("Standart (önerilen)", "Standard (recommended)")
        case .alternative1: return T("Alternatif 1", "Alternative 1")
        case .alternative2: return T("Alternatif 2", "Alternative 2")
        case .custom: return T("Özel", "Custom")
        }
    }

    @MainActor var hint: String {
        switch self {
        case .standard: return T("Çoğu engelde çalışır.", "Works for most blocks.")
        case .alternative1: return T("Standart yetmezse bunu dene.", "Try this if standard fails.")
        case .alternative2: return T("Son çare.", "Last resort.")
        case .custom: return T("Değerleri elle ayarladın.", "You set the values manually.")
        }
    }

    /// Tested on this machine against the ISP that prompted all this: chunk 2
    /// and random worked; sni dropped the handshake on discord.com, so it is
    /// reachable in the advanced picker but never a preset. Alternative 2 is
    /// now record fragmentation, which the bundled engine could not do — it
    /// used to be `disorder`, a raw-socket trick that needed root and was
    /// therefore never really running.
    var settings: (split: SplitMode, chunk: Int, dns: DNSMode)? {
        switch self {
        case .standard: return (.chunk, 2, .https)
        case .alternative1: return (.random, 3, .https)
        case .alternative2: return (.record, 40, .https)
        case .custom: return nil
        }
    }
}

/// Bir alan adı kümesi ve o kümeye uygulanacak DPI aşım ayarı.
/// Kullanıcı "discord.com" yazar; joker varyantlarını biz üretiriz.
struct DomainGroup: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var enabled: Bool = true
    var domains: [String] = []
    var dnsMode: DNSMode = .https
    var splitMode: SplitMode = .chunk
    var chunkSize: Int = 2
    var preset: BypassPreset = .standard
    /// Sıralama: büyük olan önce eşleşir. Arayüzde listedeki sıradan üretilir.
    var priority: Int = 100

    /// "discord.com" -> ["discord.com", "*.discord.com", "**.discord.com"]
    /// Zaten joker içeren girdiye dokunulmaz.
    static func expand(_ domain: String) -> [String] {
        let d = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !d.isEmpty else { return [] }
        if d.contains("*") { return [d] }
        return [d, "*.\(d)", "**.\(d)"]
    }

    init(id: UUID = UUID(), name: String, enabled: Bool = true, domains: [String] = [],
         dnsMode: DNSMode = .https, splitMode: SplitMode = .chunk, chunkSize: Int = 2,
         preset: BypassPreset = .standard, priority: Int = 100) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.domains = domains
        self.dnsMode = dnsMode
        self.splitMode = splitMode
        self.chunkSize = chunkSize
        self.preset = preset
        self.priority = priority
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "?"
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        domains = try c.decodeIfPresent([String].self, forKey: .domains) ?? []
        dnsMode = try c.decodeIfPresent(DNSMode.self, forKey: .dnsMode) ?? .https
        splitMode = try c.decodeIfPresent(SplitMode.self, forKey: .splitMode) ?? .chunk
        chunkSize = try c.decodeIfPresent(Int.self, forKey: .chunkSize) ?? 2
        preset = try c.decodeIfPresent(BypassPreset.self, forKey: .preset) ?? .standard
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 100
    }

    /// Hazır ayarı uygular; teknik alanlar buradan türetilir.
    mutating func apply(preset: BypassPreset) {
        self.preset = preset
        if let s = preset.settings {
            splitMode = s.split
            chunkSize = s.chunk
            dnsMode = s.dns
        }
    }

    var expandedDomains: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for d in domains {
            for e in DomainGroup.expand(d) where !seen.contains(e) {
                seen.insert(e)
                result.append(e)
            }
        }
        return result
    }
}

// MARK: - Otomasyon kuralları

enum Trigger: Codable, Equatable {
    /// Seçili uygulamalardan biri çalışıyorsa.
    case app(bundleIDs: [String])
    /// Belirli Wi-Fi ağında veya belirli ağ servisindeyken.
    case network(ssids: [String], serviceNames: [String])
    /// Haftanın günleri (1=Pazar ... 7=Cumartesi) ve saat aralığı, dakika cinsinden.
    case schedule(days: Set<Int>, startMinute: Int, endMinute: Int)

    var kindLabel: String {
        switch self {
        case .app: return "Uygulama"
        case .network: return "Ağ"
        case .schedule: return "Zaman"
        }
    }
}

struct AutomationRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var enabled: Bool = true
    var trigger: Trigger
}

// MARK: - Genel ayarlar

struct AppSettings: Codable, Equatable {
    var listenHost: String = "127.0.0.1"
    /// 8080 en çok çakışan geliştirme portu; varsayılan bilerek uzakta.
    var listenPort: Int = 18080
    /// Discord güncelleyicisi gibi yalnızca ortam değişkenini okuyan uygulamalar için.
    /// Motor ayakta olduğu sürece set edilir, motor durunca temizlenir.
    var manageProxyEnvVars: Bool = false
    /// Sistem proxy'sini hangi ağ servislerine uygulayacağız. Boşsa etkin olanlar
    /// otomatik bulunur (Wi-Fi sabit yazmanın tuzağına düşmemek için).
    var pinnedServices: [String] = []
    var launchAtLogin: Bool = false
    /// Teknik alanları (parçalama modu, parça boyutu, DNS) göster.
    var advancedMode: Bool = false
    var language: Language = .system
    /// Port doluysa kendiliğinden boş bir port seç.
    var autoPort: Bool = true
    /// Proxy'den muaf tutulacak adresler.
    ///
    /// Motor durduğunda ya da uygulama kapandığında sistem proxy'si geri alınır,
    /// ama `launchctl setenv` ile konan değişkeni ZATEN ÇALIŞAN süreçler
    /// bırakmaz: uzun ömürlü bir CLI (Claude Code gibi) ölü porta bağlanmaya
    /// devam eder ve ağı kesilir. DPI'nin hedef almadığı bu adresleri proxy'nin
    /// dışında tutmak hem o kazayı hem gereksiz bir atlamayı önler.
    var bypassDomains: [String] = AppSettings.defaultBypassDomains

    static let defaultBypassDomains = [
        "localhost", "127.0.0.1", "*.local", "169.254/16",
        "*.anthropic.com", "*.claude.ai", "claude.ai"
    ]

    init() {}

    /// Eksik anahtarlar varsayılana düşer. Swift'in ürettiği çözümleyici
    /// eksik anahtarda hata verir; yeni bir alan eklediğimizde kullanıcının
    /// mevcut ayar dosyası sessizce sıfırlanırdı.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        listenHost = try c.decodeIfPresent(String.self, forKey: .listenHost) ?? d.listenHost
        listenPort = try c.decodeIfPresent(Int.self, forKey: .listenPort) ?? d.listenPort
        manageProxyEnvVars = try c.decodeIfPresent(Bool.self, forKey: .manageProxyEnvVars) ?? d.manageProxyEnvVars
        pinnedServices = try c.decodeIfPresent([String].self, forKey: .pinnedServices) ?? d.pinnedServices
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        advancedMode = try c.decodeIfPresent(Bool.self, forKey: .advancedMode) ?? d.advancedMode
        language = try c.decodeIfPresent(Language.self, forKey: .language) ?? d.language
        autoPort = try c.decodeIfPresent(Bool.self, forKey: .autoPort) ?? d.autoPort
        bypassDomains = try c.decodeIfPresent([String].self, forKey: .bypassDomains) ?? d.bypassDomains
    }
}

// MARK: - Kök yapılandırma

struct AppConfig: Codable, Equatable {
    var settings = AppSettings()
    var groups: [DomainGroup] = []
    var rules: [AutomationRule] = []

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        groups = try c.decodeIfPresent([DomainGroup].self, forKey: .groups) ?? []
        rules = try c.decodeIfPresent([AutomationRule].self, forKey: .rules) ?? []
    }

    static let `default`: AppConfig = {
        var c = AppConfig()
        c.groups = [
            DomainGroup(
                name: "Discord",
                domains: ["discord.com", "discord.gg", "discordapp.com", "discordapp.net",
                          "discord.media", "discord.dev", "discord.new", "discord.gift", "dis.gd"],
                dnsMode: .https,
                splitMode: .chunk,
                chunkSize: 2,
                priority: 100
            )
        ]
        c.rules = [
            AutomationRule(name: "Discord açıkken", trigger: .app(bundleIDs: ["com.hnc.Discord"]))
        ]
        return c
    }()
}

/// Diskteki config.json'u okuyup yazan gözlemlenebilir depo.
@MainActor
final class ConfigStore: ObservableObject {
    /// Tek örnek: AppDelegate ile SwiftUI sahnesi aynı depoyu görmeli.
    static let shared = ConfigStore()

    @Published var config: AppConfig {
        didSet { if config != oldValue { save() } }
    }

    init() {
        if let data = try? Data(contentsOf: Paths.config),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = decoded
        } else {
            config = .default
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: Paths.config, options: .atomic)
    }
}
