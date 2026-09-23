import Foundation
import AppKit
import ServiceManagement

enum RunMode: String, Codable {
    case auto      // kurallar karar verir
    case forceOn   // elle açık
    case forceOff  // elle kapalı
}

/// Beyin: kuralları değerlendirir, motoru ve sistem proxy'sini birlikte
/// açıp kapatır. Motor ile proxy'nin durumu ASLA ayrışmamalı — ayrışırsa
/// ya trafik korumasız akar ya da sistem ölü porta bakar.
@MainActor
final class Supervisor: ObservableObject {
    /// Tek örnek. AppDelegate kapanış temizliğini bunun üzerinden yapar;
    /// ayrı bir örnek olsaydı kapanışta proxy geri alınmadan kalırdı.
    static let shared = Supervisor(store: .shared)

    @Published private(set) var isActive = false
    @Published private(set) var lastError: String?
    @Published private(set) var matchedRules: [String] = []
    /// Motorun gerçekten dinlediği port. Çakışma yüzünden ayarlardaki
    /// tercihten farklı olabilir; teşhis testi bunu kullanmalı.
    @Published private(set) var activePort: Int?
    @Published var mode: RunMode = .auto {
        didSet { evaluate() }
    }

    /// Geçici tutma sayacı: bir uygulamayı Kalfa ortamıyla yeniden başlatırken
    /// motorun kapanmaması gerekir. Uygulama kapanınca kural eşleşmesi düşer,
    /// motor durur, ortam değişkeni silinir ve uygulama yine korumasız başlar.
    private var holdCount = 0

    let store: ConfigStore
    private let engine: Engine
    private let appWatcher = AppWatcher()
    private let networkWatcher = NetworkWatcher()
    private let scheduleWatcher = ScheduleWatcher()

    var currentSSID: String? { networkWatcher.currentSSID }
    var activeServices: [String] { networkWatcher.activeServices }

    init(store: ConfigStore, engine: Engine = SpoofDPIEngine()) {
        self.store = store
        self.engine = engine

        // Önceki oturum çökerek kapandıysa sistem proxy'si açık kalmış olabilir.
        SystemProxyController.recoverIfDirty()

        self.engine.onUnexpectedExit = { [weak self] _ in
            guard let self else { return }
            // Motor öldüyse proxy'yi bir an bile ayakta bırakma.
            SystemProxyController.restore()
            self.isActive = false
            self.activePort = nil
            self.lastError = "Motor beklenmedik şekilde durdu. Sistem proxy'si kapatıldı."
        }
    }

    func start() {
        if Paths.bundledEngine == nil {
            lastError = "Motor ikilisi bulunamadı."
            Log.write(.error, "Motor ikilisi bulunamadı.")
        }
        Log.write(.info, "Kalfa başladı.")
        // Çökmüş ya da zorla kapatılmış önceki oturumdan kalan motorlar varsa
        // portları tutuyorlar; bizimki yanlarına bir port ötede açılırdı.
        SpoofDPIEngine.reapOrphans()
        appWatcher.start { [weak self] in self?.evaluate() }
        networkWatcher.start { [weak self] in self?.evaluate() }
        scheduleWatcher.start { [weak self] in self?.evaluate() }
        evaluate()
    }

    // MARK: Kural değerlendirme

    func evaluate() {
        let matched = store.config.rules.filter { $0.enabled && matches($0.trigger) }
        matchedRules = matched.map(\.name)

        var desired: Bool
        switch mode {
        case .auto: desired = !matched.isEmpty
        case .forceOn: desired = true
        case .forceOff: desired = false
        }
        if holdCount > 0 { desired = true }

        if desired && !isActive {
            activate()
        } else if !desired && isActive {
            deactivate()
        }
    }

    private func matches(_ trigger: Trigger) -> Bool {
        switch trigger {
        case .app(let bundleIDs):
            return bundleIDs.contains { appWatcher.isRunning($0) }
        case .network(let ssids, let serviceNames):
            if let ssid = networkWatcher.currentSSID, ssids.contains(ssid) { return true }
            return serviceNames.contains { networkWatcher.activeServices.contains($0) }
        case .schedule(let days, let start, let end):
            let now = ScheduleWatcher.now()
            guard days.isEmpty || days.contains(now.weekday) else { return false }
            return ScheduleWatcher.inRange(start: start, end: end, now: now.minute)
        }
    }

    // MARK: Aç / kapat

    /// 1024 altı ayrıcalıklı, 49152 üstü macOS'un geçici port aralığı.
    /// İkisi de motor için uygun değil.
    static func sanitizePort(_ port: Int) -> Int {
        min(max(port, 1024), 49151)
    }

    /// Port doluysa sıradaki boş portu bulur. Kullanıcı "port dolu" hatasıyla
    /// baş başa kalmasın diye varsayılan davranış budur.
    private func resolvePort(host: String, preferred: Int) -> Int? {
        let start = Self.sanitizePort(preferred)
        if !SpoofDPIEngine.isPortBusy(host: host, port: start) { return start }
        guard store.config.settings.autoPort else { return nil }
        for candidate in stride(from: start + 1, to: min(start + 40, 49151), by: 1)
        where !SpoofDPIEngine.isPortBusy(host: host, port: candidate) {
            Log.write(.warn, "\(start) portu dolu, \(candidate) portuna geçildi.")
            return candidate
        }
        return nil
    }

    private func activate() {
        lastError = nil
        activePort = nil
        var settings = store.config.settings

        guard let port = resolvePort(host: settings.listenHost, preferred: settings.listenPort) else {
            lastError = EngineError.portBusy(settings.listenPort).localizedDescription
            Log.write(.error, "Boş port bulunamadı.")
            return
        }
        // Yedek port yalnızca bu oturum için. Kullanıcının seçtiği portu
        // config'e geri yazarsak, bir kez kayan numara bir daha geri dönmez ve
        // her çakışmada bir artar; ayarlardaki değer kullanıcının tercihi kalır.
        settings.listenPort = port
        let toml = TOMLGenerator.build(from: store.config)
        do {
            try toml.write(to: Paths.engineConfig, atomically: true, encoding: .utf8)
        } catch {
            lastError = "Motor yapılandırması yazılamadı: \(error.localizedDescription)"
            return
        }

        do {
            try engine.start(configPath: Paths.engineConfig,
                             host: settings.listenHost,
                             port: settings.listenPort)
        } catch {
            lastError = error.localizedDescription
            Log.write(.error, error.localizedDescription)
            return
        }

        // Motorun dinlemeye başlaması için kısa pay; proxy'yi hazır olmadan
        // açarsak ilk istekler düşer.
        Thread.sleep(forTimeInterval: 0.4)

        let services = SystemProxyController.targetServices(config: settings)
        let ok = SystemProxyController.enable(host: settings.listenHost,
                                              port: settings.listenPort,
                                              services: services,
                                              envVars: settings.manageProxyEnvVars,
                                              bypass: settings.bypassDomains)
        if !ok {
            // Proxy kurulamadıysa motoru da bırakma; yarım durum en kötüsü.
            engine.stop()
            lastError = "Sistem proxy'si ayarlanamadı."
            return
        }
        activePort = port
        isActive = true
    }

    private func deactivate() {
        // Sıra önemli: önce sistem proxy'si geri alınır, sonra motor durur.
        // Tersi olursa aradaki kısa sürede tüm trafik ölü porta gider.
        SystemProxyController.restore()
        engine.stop()
        isActive = false
        activePort = nil
    }

    // MARK: Uygulamayı Kalfa ortamıyla yeniden başlatma

    /// Discord güncelleyicisi gibi araçlar `https_proxy` değişkenini yalnızca
    /// BAŞLARKEN bir kez okur. Uygulama zaten açıkken Kalfa devreye girdiğinde
    /// güncelleyici değişkeni göremez ve doğrudan çıkıp ISS'nin sertifikasına
    /// takılır. Çözüm: motoru ayakta tut, değişkeni kur, uygulamayı yeniden başlat.
    func relaunchWithProxy(bundleID: String) async {
        holdCount += 1
        defer { holdCount -= 1 }

        Log.write(.info, "Yeniden başlatma istendi: \(bundleID)")
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            lastError = T("Uygulama bulunamadı.", "App not found.")
            Log.write(.error, "Uygulama bulunamadı: \(bundleID)")
            return
        }

        // Ortam değişkeni yönetimi kapalıysa aç. Yeniden başlatmanın tek amacı
        // uygulamanın değişkeni görmesi; kapalıyken düğme anlamsız olurdu.
        if !store.config.settings.manageProxyEnvVars {
            store.config.settings.manageProxyEnvVars = true
            Log.write(.info, "Yeniden başlatma için ortam değişkeni yönetimi açıldı.")
        }

        // Taze bir açılış: kirli durum dosyasına "ortam değişkeni kuruldu"
        // bilgisi de yazılsın. Aksi halde kapanışta değişken temizlenmez ve
        // ölü porta işaret eden bir https_proxy geride kalır.
        if isActive { deactivate() }
        activate()
        guard isActive else {
            lastError = T("Kalfa başlatılamadı, uygulama yeniden başlatılmadı.",
                          "Kalfa could not start, the app was not relaunched.")
            Log.write(.error, "Motor açılamadığı için yeniden başlatma iptal edildi.")
            return
        }

        // Açıksa nazikçe kapat ve gerçekten çıkmasını bekle.
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in running { app.terminate() }
        for _ in 0..<40 where !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            lastError = T("Uygulama kapanmadı, elle kapatıp tekrar dene.",
                          "The app did not quit. Close it manually and try again.")
            Log.write(.error, "\(bundleID) kapanmadı, yeniden başlatma yarıda kaldı.")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            Log.write(.info, "\(bundleID) Kalfa ortamıyla yeniden başlatıldı.")
        } catch {
            lastError = T("Uygulama açılamadı: \(error.localizedDescription)",
                          "Could not open the app: \(error.localizedDescription)")
            return
        }

        // Uygulama ayağa kalkıp kuralı tekrar tetikleyene kadar tutmayı sürdür.
        try? await Task.sleep(nanoseconds: 4_000_000_000)
    }

    /// Kurallarda geçen, yeniden başlatılabilecek uygulamalar.
    var ruleAppBundleIDs: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for rule in store.config.rules {
            if case .app(let ids) = rule.trigger {
                for id in ids where !seen.contains(id) {
                    seen.insert(id)
                    result.append(id)
                }
            }
        }
        return result
    }

    /// Menüdeki acil düğme. Ne olursa olsun sistemi eski hâline döndürür.
    func panic() {
        SystemProxyController.restore()
        SystemProxyController.unsetEnvVars()
        engine.stop()
        isActive = false
        mode = .forceOff
        Log.write(.warn, "Acil kapatma: proxy geri alındı, motor durduruldu.")
    }

    /// Ayar değiştiğinde çağrılır. Motor TOML'u başlarken bir kez okuduğu için
    /// açıkken değişiklik uygulamak yeniden başlatma gerektirir.
    func applyConfigChange() {
        store.save()
        guard isActive else { evaluate(); return }
        Log.write(.info, "Yapılandırma değişti, motor yeniden başlatılıyor.")
        deactivate()
        activate()
    }

    func shutdown() {
        if isActive { deactivate() }
        SystemProxyController.unsetEnvVars()
    }

    // MARK: Girişte başlat

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            store.config.settings.launchAtLogin = enabled
        } catch {
            lastError = "Girişte başlatma ayarlanamadı: \(error.localizedDescription)"
        }
    }
}
