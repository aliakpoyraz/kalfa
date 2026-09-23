import Darwin
import Foundation
import IOKit
import IOKit.ps

/// Ağ, pil ve GPU. Üçü de tek bir çekirdek çağrısına inmediği için ayrı durur.
enum DeviceStats {

    // MARK: Ağ

    /// Arayüzlerin biriken bayt sayaçları. Hız FARKTAN çıkar.
    struct NetCounters: Sendable {
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        var sampledAt = Date()
    }

    static func netCounters() -> NetCounters {
        var counters = NetCounters()
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return counters }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            // Yalnızca bağlantı katmanı kayıtları sayaç taşır; IP kayıtları aynı
            // arayüzü tekrar sayardı.
            guard entry.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  let data = entry.pointee.ifa_data else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            // Geri döngü gerçek trafik değil; saymak yerel proxy'yi iki kez sayar.
            guard !name.hasPrefix("lo") else { continue }

            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            counters.bytesIn &+= UInt64(stats.ifi_ibytes)
            counters.bytesOut &+= UInt64(stats.ifi_obytes)
        }
        return counters
    }

    static func netRate(from old: NetCounters, to new: NetCounters) -> NetworkRate {
        var rate = NetworkRate()
        let elapsed = new.sampledAt.timeIntervalSince(old.sampledAt)
        guard elapsed > 0 else { return rate }
        // Sayaç taşması ya da arayüzün sıfırlanması negatif fark üretir; atılır.
        if new.bytesIn >= old.bytesIn {
            rate.inPerSecond = Double(new.bytesIn &- old.bytesIn) / elapsed
        }
        if new.bytesOut >= old.bytesOut {
            rate.outPerSecond = Double(new.bytesOut &- old.bytesOut) / elapsed
        }
        return rate
    }

    // MARK: Pil

    static func power() -> PowerState? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                    as? [String: Any] else { continue }
            guard let capacity = info[kIOPSCurrentCapacityKey] as? Int,
                  let max = info[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }

            let charging = info[kIOPSIsChargingKey] as? Bool ?? false
            let plugged = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            // Sistem hesaplarken -1 döner; "kalan süre bilinmiyor" demektir.
            let minutes = info[kIOPSTimeToEmptyKey] as? Int
            return PowerState(percentage: Int((Double(capacity) / Double(max) * 100).rounded()),
                              isCharging: charging,
                              isPluggedIn: plugged,
                              minutesRemaining: (minutes ?? -1) > 0 ? minutes : nil)
        }
        return nil
    }

    // MARK: GPU

    /// Sürücünün bildirdiği kullanım oranı (0...1).
    ///
    /// Anahtar isimleri Apple'ın belgelediği bir sözleşme değil; sürücüye göre
    /// değişir ve bir gün kaybolabilir. Bulunamazsa gösterge hiç çizilmez —
    /// uydurulmuş bir sayı göstermekten iyidir.
    static func gpuUtilization() -> Double? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dictionary = properties?.takeRetainedValue() as? [String: Any],
                  let performance = dictionary["PerformanceStatistics"] as? [String: Any]
            else { continue }

            for key in ["Device Utilization %", "GPU Activity(%)", "Renderer Utilization %"] {
                if let value = performance[key] as? Int {
                    best = max(best ?? 0, Double(value) / 100)
                    break
                }
            }
        }
        return best
    }
}
