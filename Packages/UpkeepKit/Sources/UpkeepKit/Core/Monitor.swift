import Combine
import Foundation

/// Tek bir turun ham çıktısı. Örnekleyiciden arayüze geçen tek paket.
struct Reading: Sendable {
    var sample: Sample
    /// Yalnızca süreç tablosunun toplandığı turlarda dolu.
    var processes: [ProcessRow]?
}

/// Ölçümü alan yarım. Bir seri kuyruk üzerine hapsedilmiştir: fark almak için
/// önceki turu saklamak zorunda ve o durum başka bir iş parçacığından
/// okunursa yüzdeler bozulur.
private final class Sampler: @unchecked Sendable {

    /// Süreç tablosu diğer ölçümlerden pahalı; her turda değil, üç turda bir.
    private let processInterval = 3

    private let processes = ProcessTable()
    private var lastCPU: HostStats.CPUTicks?
    private var lastNet: DeviceStats.NetCounters?
    private var tick = 0

    func reset() {
        processes.reset()
        lastCPU = nil
        lastNet = nil
        tick = 0
    }

    func next() -> Reading {
        var sample = Sample()
        sample.memory = HostStats.memory()
        sample.disk = HostStats.disk()
        sample.gpu = DeviceStats.gpuUtilization()
        sample.power = DeviceStats.power()

        if let ticks = HostStats.cpuTicks() {
            if let lastCPU { sample.cpu = HostStats.cpuUsage(from: lastCPU, to: ticks) }
            lastCPU = ticks
        }

        let counters = DeviceStats.netCounters()
        if let lastNet { sample.network = DeviceStats.netRate(from: lastNet, to: counters) }
        lastNet = counters

        let wantsProcesses = tick % processInterval == 0
        tick &+= 1

        return Reading(sample: sample,
                       processes: wantsProcesses ? processes.snapshot() : nil)
    }
}

/// Canlı ölçüm kaynağı.
///
/// Tek örnek, ama açılışta çalışmaya başlamaz: `retain()` çağrılana kadar hiç
/// örnek almaz. Panel kapalıyken saniyede bir ölçmek, kullanıcı hiçbir şeye
/// bakmazken pil yakmak olurdu — gösterge kendisi listenin en üstüne çıkardı.
@MainActor
public final class Monitor: ObservableObject {

    public static let shared = Monitor()

    @Published public private(set) var sample = Sample()
    @Published public private(set) var processes: [ProcessRow] = []
    /// Kıvılcım çizgisi için son değerler; en yenisi sonda.
    @Published public private(set) var cpuHistory: [Double] = []
    @Published public private(set) var memoryHistory: [Double] = []

    /// Grafiğin taşıdığı süre: 60 örnek × 1 saniye.
    private let historyLength = 60

    private let sampler = Sampler()
    private let queue = DispatchQueue(label: "com.aliakpoyraz.kalfa.monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var viewers = 0

    private init() {}

    // MARK: Yaşam döngüsü

    /// Göstergeyi açan her görünüm bunu çağırır, kapanırken `release()`.
    /// Sayaçla çalışır: panel ve pencere aynı anda açıkken iki kez ölçülmez.
    public func retain() {
        viewers += 1
        guard viewers == 1 else { return }

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: 1.0, leeway: .milliseconds(200))
        source.setEventHandler { [weak self, sampler] in
            let reading = sampler.next()
            Task { @MainActor in self?.apply(reading) }
        }
        timer = source
        source.resume()
    }

    public func release() {
        viewers = max(viewers - 1, 0)
        guard viewers == 0 else { return }

        timer?.cancel()
        timer = nil
        // Sıfırlama kuyrukta: örnekleyiciye yalnızca oradan dokunulur.
        queue.async { [sampler] in sampler.reset() }
    }

    // MARK: Yayımlama

    private func apply(_ reading: Reading) {
        sample = reading.sample
        append(&cpuHistory, reading.sample.cpu.total)
        append(&memoryHistory, reading.sample.memory.usedFraction)
        if let rows = reading.processes { processes = rows }
    }

    private func append(_ series: inout [Double], _ value: Double) {
        series.append(value)
        if series.count > historyLength {
            series.removeFirst(series.count - historyLength)
        }
    }

    // MARK: Türetilmiş görünümler

    public func topByCPU(limit: Int = 5) -> [ProcessRow] {
        Array(processes.sorted { $0.cpu > $1.cpu }.prefix(limit))
    }

    public func topByMemory(limit: Int = 5) -> [ProcessRow] {
        Array(processes.sorted { $0.memory > $1.memory }.prefix(limit))
    }
}
