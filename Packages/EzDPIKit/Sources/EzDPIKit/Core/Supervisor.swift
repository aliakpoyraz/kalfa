import Foundation
import AppKit
import ServiceManagement
import KalfaUI

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

    /// Açma/kapama sırası girişken olmamalı: uygulama izleyicisi, ağ izleyicisi
    /// ve zamanlayıcı birbiri ardına `evaluate()` çağırabiliyor. Biri motoru
    /// kurarken ikincisi araya girerse aynı porta iki kez bağlanmaya çalışırız.
    private var isTransitioning = false

    let store: ConfigStore
    private let engine: Engine
    private let appWatcher = AppWatcher()
    private let networkWatcher = NetworkWatcher()
    private let scheduleWatcher = ScheduleWatcher()

    var currentSSID: String? { networkWatcher.currentSSID }
    var activeServices: [String] { networkWatcher.activeServices }

    init(store: ConfigStore, engine: Engine = NativeEngine()) {
        self.store = store
        self.engine = engine

        // Önceki oturum çökerek kapandıysa sistem proxy'si açık kalmış olabilir.
        SystemProxyController.recoverIfDirty()

        self.engine.onUnexpectedExit = { [weak self] reason in
            guard let self else { return }
            // Motor düştüyse proxy'yi bir an bile ayakta bırakma; sistem ölü
            // porta bakarsa internet tamamen kesilir.
            SystemProxyController.restore()
            self.isActive = false
            self.activePort = nil
            self.lastError = "Motor durdu (\(reason)). Sistem proxy'si kapatıldı."
        }
    }

    func start() {
        Log.write(.info, "Kalfa başladı.")
        // Yetim motor avı kalktı: motor artık bu sürecin içinde, uygulama
        // kapanınca dinleyici de kapanıyor. Eski sürümde çöken her oturum
        // arkasında bir port tutan süreç bırakıyordu.
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

        guard !isTransitioning else { return }
        if desired && !isActive {
            Task { await activate() }
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

    /// Motoru kurar, ANCAK gerçekten dinlemeye başladıktan sonra sistem
    /// proxy'sini açar.
    ///
    /// Sıra burada hayati: proxy açıkken motor yoksa makine ölü bir porta bakar
    /// ve internet tamamen kesilir — kullanıcının teşhis edemeyeceği tek arıza
    /// budur. Eskiden `engine.start` dinleyici kurulmadan dönüyordu, bağlanma
    /// hatası saniyenin binde biri sonra geliyordu ve proxy o sırada çoktan
    /// açılmış oluyordu.
    private func activate() async {
        guard !isTransitioning else { return }
        isTransitioning = true
        defer { isTransitioning = false }

        lastError = nil
        activePort = nil
        var settings = store.config.settings

        // Portun boş olup olmadığının tek dürüst cevabı bağlanmayı denemek.
        // Önceki sürümdeki yoklama NWListener'ı kurup hiç başlatmıyordu; bağlama
        // `start()`'ta olduğu için o yoklama her zaman "boş" diyordu.
        let first = Self.sanitizePort(settings.listenPort)
        let candidates = store.config.settings.autoPort
            ? Array(stride(from: first, to: min(first + 20, 49151), by: 1))
            : [first]

        var started = false
        for candidate in candidates {
            do {
                try await engine.start(config: store.config,
                                       host: settings.listenHost,
                                       port: candidate)
                // Yedek port yalnızca bu oturum için: kullanıcının seçtiği
                // numarayı config'e geri yazarsak bir kez kayan port bir daha
                // geri dönmez ve her çakışmada bir artar.
                settings.listenPort = candidate
                started = true
                if candidate != first {
                    Log.write(.warn, "\(first) portu dolu, \(candidate) portuna geçildi.")
                }
                break
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }

        guard started else {
            Log.write(.error, lastError ?? "Motor başlatılamadı.")
            return
        }
        lastError = nil

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
        activePort = settings.listenPort
        isActive = true
    }

    /// Yeniden başlatma yolunda kullanılan hâli: portun gerçekten serbest
    /// kalmasını bekler. Beklemezsek yeni dinleyici eskisi hâlâ portu tutarken
    /// bağlanmaya çalışır ve "Address already in use" alır.
    private func deactivateAndWait() async {
        SystemProxyController.restore()
        await engine.stopAndWait()
        isActive = false
        activePort = nil
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
            lastError = L10n.t("dpi.engine.app-not-found")
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
        if isActive { await deactivateAndWait() }
        await activate()
        guard isActive else {
            lastError = L10n.t("dpi.engine.kalfa-could-not-start")
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
            lastError = L10n.t("dpi.engine.app-did-not-quit")
            Log.write(.error, "\(bundleID) kapanmadı, yeniden başlatma yarıda kaldı.")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            Log.write(.info, "\(bundleID) Kalfa ortamıyla yeniden başlatıldı.")
        } catch {
            lastError = L10n.t("dpi.engine.could-not-open-app", "\(error.localizedDescription)")
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

    /// Ayar değiştiğinde çağrılır.
    ///
    /// Kural tablosu motorun içinde durduğu için alan adı ve yöntem
    /// değişiklikleri anında geçerli olur — eski motor TOML'u yalnızca
    /// başlarken okuduğundan her küçük düzenleme bağlantıları koparan bir
    /// yeniden başlatma demekti. Yalnızca dinlenen adres değişirse yeniden
    /// başlatmak gerekir.
    func applyConfigChange(restart: Bool = false) {
        store.save()
        guard isActive else { evaluate(); return }
        if restart {
            Log.write(.info, "Dinlenen adres değişti, motor yeniden başlatılıyor.")
            Task {
                await deactivateAndWait()
                await activate()
            }
        } else {
            engine.updateRules(config: store.config)
            Log.write(.info, "Kural tablosu güncellendi.")
        }
    }

    func shutdown() {
        // Koşulsuz geri alma. `isActive` yanlışlıkla false olduğu hâlde proxy
        // açık kalabiliyor — motor kendiliğinden düştüğünde tam olarak bu olur.
        // O durumda çıkarken geri almazsak kullanıcı internetsiz kalır ve
        // sebebini gösteren hiçbir şey ekranda olmaz.
        SystemProxyController.restore()
        engine.stop()
        isActive = false
        activePort = nil
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
