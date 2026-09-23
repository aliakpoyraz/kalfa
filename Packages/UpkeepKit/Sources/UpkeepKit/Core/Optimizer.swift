import Foundation

/// Sistem bakım işlemleri.
///
/// **Neyin dahil OLMADIĞI da bir karar.** "Hızlandırıcı" araçların çoğu belleği
/// boşaltan (`purge`), takas dosyasını silen, RAM'i "temizleyen" düğmeler koyar.
/// Bunlar macOS'ta ya etkisiz ya zararlıdır: çekirdek belleği zaten yönetir,
/// zorla boşaltmak yalnızca bir sonraki erişimi diskten okutur. Buraya yalnızca
/// ne yaptığı tek cümleyle açıklanabilen ve etkisi gözlemlenebilen işler girdi.
public enum Optimizer {

    public struct Task: Sendable, Identifiable, Equatable {
        public var id: String { rawValue }
        public var rawValue: String
        /// Yönetici parolası ister mi? Arayüz bunu ÖNCEDEN söyler; parola
        /// kutusunun sebepsiz açılması güven kaybıdır.
        public var needsAdmin: Bool
        /// İşlem sırasında ekranın kısa süre bozulması gibi görünür bir yan
        /// etkisi var mı?
        public var disruptive: Bool

        init(_ rawValue: String, needsAdmin: Bool = false, disruptive: Bool = false) {
            self.rawValue = rawValue
            self.needsAdmin = needsAdmin
            self.disruptive = disruptive
        }
    }

    /// DNS önbelleği: ad kaydı değiştiyse makine eskisini tutmayı sürdürür.
    public static let flushDNS = Task("flushDNS", needsAdmin: true)
    /// Launch Services: "Birlikte Aç" listesindeki ölü kayıtlar ve yanlış
    /// uygulama ikonları buradan gelir.
    public static let rebuildLaunchServices = Task("rebuildLaunchServices")
    /// Quick Look: boşluk tuşuyla açılan önizlemenin eski içeriği göstermesi.
    public static let resetQuickLook = Task("resetQuickLook")
    /// Finder ve Dock: takılı kalan pencereler, güncellenmeyen ikonlar.
    public static let restartFinderDock = Task("restartFinderDock", disruptive: true)
    /// Spotlight dizini: arama sonuç vermiyorsa. PAHALI — yeniden dizinleme
    /// saatler sürer ve o sürede makine yavaşlar.
    public static let reindexSpotlight = Task("reindexSpotlight", needsAdmin: true, disruptive: true)

    public static let all: [Task] = [
        flushDNS, rebuildLaunchServices, resetQuickLook, restartFinderDock, reindexSpotlight
    ]

    // MARK: Çalıştırma

    public enum TaskError: LocalizedError {
        case failed(String)
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .failed(let message): return message
            case .cancelled: return "Vazgeçildi."
            }
        }
    }

    /// Çağıran iş parçacığını bloklar; arka planda çağrılmalı.
    public static func run(_ task: Task) throws {
        switch task.rawValue {
        case flushDNS.rawValue:
            // İki adım birlikte olmalı: önbelleği boşaltmak yetmez, çözümleyici
            // kendi kopyasını tutar ve yeniden yüklenmeden eskisini vermeyi sürdürür.
            try admin("dscacheutil -flushcache; killall -HUP mDNSResponder")

        case rebuildLaunchServices.rawValue:
            let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks"
                + "/LaunchServices.framework/Support/lsregister"
            try shell(lsregister, ["-kill", "-r", "-domain", "local", "-domain", "user"])

        case resetQuickLook.rawValue:
            try shell("/usr/bin/qlmanage", ["-r"])
            try shell("/usr/bin/qlmanage", ["-r", "cache"])

        case restartFinderDock.rawValue:
            // Sırayla ve hatasız: biri çalışmıyorsa killall hata döner, bu
            // beklenen bir durum ve işlemi başarısız saymamalı.
            _ = try? shell("/usr/bin/killall", ["Finder"])
            _ = try? shell("/usr/bin/killall", ["Dock"])

        case reindexSpotlight.rawValue:
            try admin("mdutil -E / >/dev/null")

        default:
            throw TaskError.failed("Bilinmeyen işlem: \(task.rawValue)")
        }
    }

    // MARK: Kabuk

    @discardableResult
    private static func shell(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do { try process.run() } catch {
            throw TaskError.failed("Çalıştırılamadı: \((path as NSString).lastPathComponent)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let output = String(data: data, encoding: .utf8) ?? ""
            throw TaskError.failed(output.isEmpty
                                   ? "\((path as NSString).lastPathComponent) hata verdi."
                                   : String(output.prefix(200)))
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Yönetici hakkı gereken komutlar.
    ///
    /// Parola Kalfa'ya HİÇ girmiyor: sistem kendi kutusunu açar, komutu kendi
    /// çalıştırır. Parolayı uygulamanın içinde bir alana yazdırmak, onu bir kez
    /// bellekte tutmak demek olurdu.
    private static func admin(_ command: String) throws {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
                             .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw TaskError.failed("Betik kurulamadı.")
        }
        script.executeAndReturnError(&error)

        if let error {
            // -128: kullanıcı parola kutusunu kapattı. Hata değil, karar.
            if (error[NSAppleScript.errorNumber] as? Int) == -128 { throw TaskError.cancelled }
            throw TaskError.failed((error[NSAppleScript.errorMessage] as? String) ?? "Yönetici işlemi başarısız.")
        }
    }
}
