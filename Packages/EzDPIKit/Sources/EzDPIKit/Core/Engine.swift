import Foundation

enum EngineError: LocalizedError {
    case binaryMissing
    case portBusy(Int)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "Motor ikilisi bulunamadı. Uygulama paketi eksik olabilir."
        case .portBusy(let p):
            return "\(p) portu başkası tarafından kullanılıyor. Ayarlardan portu değiştir."
        case .launchFailed(let m):
            return "Motor başlatılamadı: \(m)"
        }
    }
}

/// Motor soyutlaması. Bugün gömülü spoofdpi ikilisini yönetiyoruz; kendi
/// çatalımız veya bir Network Extension geldiğinde yalnızca bu protokolün
/// yeni bir uygulaması yazılır, üstteki kural ve arayüz katmanı aynı kalır.
protocol Engine: AnyObject {
    var isRunning: Bool { get }
    /// Motor kendiliğinden (çökerek) durduğunda çağrılır.
    var onUnexpectedExit: ((Int32) -> Void)? { get set }
    func start(configPath: URL, host: String, port: Int) throws
    func stop()
}

final class SpoofDPIEngine: Engine {
    private var process: Process?
    private var stopping = false
    var onUnexpectedExit: ((Int32) -> Void)?

    var isRunning: Bool { process?.isRunning ?? false }

    func start(configPath: URL, host: String, port: Int) throws {
        guard !isRunning else { return }
        guard let binary = Paths.bundledEngine else { throw EngineError.binaryMissing }
        if Self.isPortBusy(host: host, port: port) { throw EngineError.portBusy(port) }

        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "--no-tui",
            "--listen-addr", "\(host):\(port)",
            "--config", configPath.path
        ]

        // Motor çıktısı ayrı dosyaya akar; teşhis sekmesi bunu okur.
        FileManager.default.createFile(atPath: Paths.engineLog.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: Paths.engineLog) {
            _ = try? handle.seekToEnd()
            process.standardOutput = handle
            process.standardError = handle
        }

        stopping = false
        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            let code = proc.terminationStatus
            DispatchQueue.main.async {
                // Yalnızca şu an sahip olduğumuz süreç için geçerli. `stop()`
                // ana kuyrukta beklerken kapanan sürecin bildirimi sıraya girer
                // ve ancak `start()` bittikten sonra çalışabilir. Kimlik
                // kontrolü olmazsa o gecikmiş bildirim yeni motorun tutamağını
                // siler, "beklenmedik şekilde durdu" diye yanlış rapor eder ve
                // yeniden açılışta port bir artar — yetimler böyle birikiyordu.
                guard self.process === proc else { return }
                self.process = nil
                if !self.stopping {
                    Log.write(.error, "Motor beklenmedik şekilde durdu (çıkış kodu \(code)).")
                    self.onUnexpectedExit?(code)
                }
            }
        }

        do {
            try process.run()
        } catch {
            throw EngineError.launchFailed("\(error)")
        }
        self.process = process
        Log.write(.info, "Motor başladı (\(host):\(port), pid \(process.processIdentifier)).")
    }

    func stop() {
        guard let process, process.isRunning else { return }
        stopping = true
        process.terminate()
        // Nazik kapanmaya kısa süre tanı, sonra kesin öldür.
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        self.process = nil
        Log.write(.info, "Motor durduruldu.")
    }

    /// Önceki çalışmadan kalmış, artık sahibi olmayan motorları kapatır.
    ///
    /// Motor uygulamanın çocuğu; uygulama zorla kapatılınca ya da çökünce çocuk
    /// hayatta kalıyor. Sonraki açılışta portu dolu bulup `autoPort` ile bir
    /// sonrakine geçiyoruz ve yetimler birikiyor — bu kod yazılırken makinede
    /// dokuz tane vardı, 18083'ten 18093'e kadar. Yalnızca bu uygulamanın
    /// ürettiği config dosyasını argümanında taşıyan süreçler seçiliyor, yani
    /// makinedeki başka bir spoofdpi'ye dokunulmaz.
    static func reapOrphans() {
        let result = Shell.run("/usr/bin/pgrep", ["-f", Paths.engineConfig.path], timeout: 5)
        let pids = result.stdout
            .split(whereSeparator: \.isNewline)
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 != getpid() }
        guard !pids.isEmpty else { return }

        for pid in pids { kill(pid, SIGTERM) }
        usleep(300_000)
        for pid in pids where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        Log.write(.warn, "\(pids.count) yetim motor süreci kapatıldı.")
    }

    /// Port dolu mu? Kendi eski sürecimiz ya da başka bir proxy olabilir.
    static func isPortBusy(host: String, port: Int) -> Bool {
        let result = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"], timeout: 5)
        return result.ok && !result.stdout.isEmpty
    }
}
