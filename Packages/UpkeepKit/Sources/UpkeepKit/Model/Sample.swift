import Foundation

/// Bir anlık ölçüm. Değer tipi: örnekleyici arka planda üretir, arayüz ana
/// iş parçacığında okur; arada paylaşılan değişken kalmaz.
public struct Sample: Sendable, Equatable {
    public var cpu = CPUUsage()
    public var memory = MemoryUsage()
    public var disk = DiskUsage()
    public var network = NetworkRate()
    public var gpu: Double?
    public var power: PowerState?
    public var takenAt = Date()

    public init() {}
}

/// Yüzdeler 0...1 aralığında. Arayüzde biçimlendirilir, burada ham durur.
public struct CPUUsage: Sendable, Equatable {
    public var user = 0.0
    public var system = 0.0
    public var idle = 1.0
    /// Çekirdek başına toplam kullanım; yük dağılımını göstermek için.
    public var perCore: [Double] = []

    public var total: Double { min(max(user + system, 0), 1) }
    public init() {}
}

public struct MemoryUsage: Sendable, Equatable {
    public var total: UInt64 = 0
    /// macOS'un "Kullanılan Bellek"i: uygulama belleği + sabitlenmiş + sıkıştırılmış.
    public var used: UInt64 = 0
    public var appMemory: UInt64 = 0
    public var wired: UInt64 = 0
    public var compressed: UInt64 = 0
    public var cached: UInt64 = 0
    public var swapUsed: UInt64 = 0
    /// Sistemin bildirdiği bellek baskısı. Yüzdeden daha dürüst bir sinyal:
    /// macOS boş RAM'i disk önbelleğine verir, "%90 dolu" tek başına kötü değil.
    public var pressure: Pressure = .normal

    public enum Pressure: Int, Sendable, Equatable {
        case normal = 1, warning = 2, critical = 4
    }

    public var usedFraction: Double {
        total == 0 ? 0 : Double(used) / Double(total)
    }
    public init() {}
}

public struct DiskUsage: Sendable, Equatable {
    public var total: UInt64 = 0
    public var free: UInt64 = 0
    /// Silinebilir alan (anlık görüntüler, temizlenebilir önbellek) hariç değil:
    /// kullanıcının Finder'da gördüğü rakamla aynı kalsın diye APFS'in bildirdiği
    /// "önemli boş alan" kullanılır.
    public var used: UInt64 { total > free ? total - free : 0 }
    public var usedFraction: Double {
        total == 0 ? 0 : Double(used) / Double(total)
    }
    public init() {}
}

/// Saniyedeki bayt. Fark alınarak üretilir; ilk örnekte sıfırdır.
public struct NetworkRate: Sendable, Equatable {
    public var inPerSecond: Double = 0
    public var outPerSecond: Double = 0
    public init() {}
}

public struct PowerState: Sendable, Equatable {
    public var percentage: Int
    public var isCharging: Bool
    public var isPluggedIn: Bool
    /// Kalan dakika; sistem henüz hesaplamadıysa nil.
    public var minutesRemaining: Int?
    public init(percentage: Int, isCharging: Bool, isPluggedIn: Bool, minutesRemaining: Int?) {
        self.percentage = percentage
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.minutesRemaining = minutesRemaining
    }
}

/// Süreç tablosundaki tek satır.
public struct ProcessRow: Sendable, Equatable, Identifiable {
    public var id: Int32 { pid }
    public var pid: Int32
    public var name: String
    /// 0...1 değil: tek çekirdeği doldurmak 1.0, sekiz çekirdek 8.0 olabilir.
    public var cpu: Double
    public var memory: UInt64
    public init(pid: Int32, name: String, cpu: Double, memory: UInt64) {
        self.pid = pid
        self.name = name
        self.cpu = cpu
        self.memory = memory
    }
}
