import Darwin
import Foundation

/// CPU ve bellek ölçümü, doğrudan çekirdekten.
///
/// `ps` ya da `top` çağırmak saniyede bir süreç doğurmak demek; menü çubuğunda
/// sürekli açık duran bir gösterge için kabul edilemez. Mach arayüzleri aynı
/// veriyi süreç doğurmadan verir.
enum HostStats {

    // MARK: CPU

    /// Mach'in çekirdek başına biriktirdiği tik sayaçları. Kullanım oranı iki
    /// örnek arasındaki FARKTAN çıkar; tek örnek yalnızca açılıştan beri geçen
    /// toplamı verir ve o sayı hiçbir zaman anlık yükü göstermez.
    struct CPUTicks: Sendable {
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0
        var perCore: [(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)] = []

        var busy: UInt64 { user &+ system &+ nice }
        var all: UInt64 { busy &+ idle }
    }

    static func cpuTicks() -> CPUTicks? {
        var count = mach_msg_type_number_t(0)
        var cores: natural_t = 0
        var info: processor_info_array_t?

        let result = host_processor_info(mach_host_self(),
                                         PROCESSOR_CPU_LOAD_INFO,
                                         &cores,
                                         &info,
                                         &count)
        guard result == KERN_SUCCESS, let info else { return nil }
        // host_processor_info kendi belleğini ayırır; bırakmazsak her örnekte sızar.
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: info),
                          vm_size_t(Int(count) * MemoryLayout<integer_t>.stride))
        }

        var ticks = CPUTicks()
        ticks.perCore.reserveCapacity(Int(cores))
        for core in 0..<Int(cores) {
            let base = core * Int(CPU_STATE_MAX)
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            ticks.user &+= user
            ticks.system &+= system
            ticks.idle &+= idle
            ticks.nice &+= nice
            ticks.perCore.append((user, system, idle, nice))
        }
        return ticks
    }

    /// İki tik örneği arasındaki kullanım. Örnekler eşitse (aynı anda iki kez
    /// okunmuşsa) bölme yapılmaz.
    static func cpuUsage(from old: CPUTicks, to new: CPUTicks) -> CPUUsage {
        var usage = CPUUsage()
        let span = new.all &- old.all
        guard span > 0 else { return usage }

        let denominator = Double(span)
        usage.user = Double((new.user &+ new.nice) &- (old.user &+ old.nice)) / denominator
        usage.system = Double(new.system &- old.system) / denominator
        usage.idle = Double(new.idle &- old.idle) / denominator

        guard old.perCore.count == new.perCore.count else { return usage }
        usage.perCore = zip(old.perCore, new.perCore).map { was, now in
            let all = (now.user &+ now.system &+ now.idle &+ now.nice)
                &- (was.user &+ was.system &+ was.idle &+ was.nice)
            guard all > 0 else { return 0 }
            let busy = (now.user &+ now.system &+ now.nice)
                &- (was.user &+ was.system &+ was.nice)
            return min(Double(busy) / Double(all), 1)
        }
        return usage
    }

    // MARK: Bellek

    static func memory() -> MemoryUsage {
        var usage = MemoryUsage()
        usage.total = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return usage }

        let page = UInt64(vm_kernel_page_size)
        usage.wired = UInt64(stats.wire_count) * page
        usage.compressed = UInt64(stats.compressor_page_count) * page
        // Dosya destekli sayfaların "purgeable" kısmı boşaltılabilir; macOS onu
        // kullanılan bellekten saymaz, biz de saymıyoruz.
        usage.cached = UInt64(stats.external_page_count) * page
        let app = UInt64(stats.internal_page_count &- stats.purgeable_count) * page
        usage.appMemory = app
        usage.used = app + usage.wired + usage.compressed
        usage.pressure = pressure()

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.stride
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            usage.swapUsed = swap.xsu_used
        }
        return usage
    }

    /// Çekirdeğin kendi baskı seviyesi. Boş RAM yüzdesinden daha dürüst: macOS
    /// kullanılmayan belleği disk önbelleğine verir, dolu görünmesi sorun değildir.
    private static func pressure() -> MemoryUsage.Pressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.stride
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .normal
        }
        return MemoryUsage.Pressure(rawValue: Int(level)) ?? .normal
    }

    // MARK: Disk

    static func disk(at path: String = NSHomeDirectory()) -> DiskUsage {
        var usage = DiskUsage()
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else { return usage }

        usage.total = UInt64(values.volumeTotalCapacity ?? 0)
        // "Önemli kullanım için uygun": Finder'ın gösterdiği rakam. Ham boş alan
        // silinebilir anlık görüntüleri saymaz ve kullanıcıya yalan söyler.
        usage.free = UInt64(max(values.volumeAvailableCapacityForImportantUsage ?? 0, 0))
        return usage
    }
}
