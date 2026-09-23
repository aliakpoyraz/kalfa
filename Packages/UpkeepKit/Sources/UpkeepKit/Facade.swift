import Foundation

/// App hedefinin UpkeepKit'te görmesine izin verilen yüzey.
///
/// Arayüz bilerek burada değil: `KalfaDesign` app hedefinde yaşıyor ve
/// göstergeler panelin geri kalanıyla aynı aralık, yazı ve renk ölçeğini
/// kullanmalı. Modül veriyi verir, çizimi panelin dili yapar.
@MainActor
public enum Upkeep {

    /// Canlı ölçüm kaynağı. Bir görünüm göstermeye başlarken `retain()`,
    /// kaybolurken `release()` çağırır; hiç izleyen yoksa örnek alınmaz.
    public static var monitor: Monitor { .shared }

    /// Disk analizi: tarama, gezinme, çöpe taşıma.
    public static var disk: DiskAnalysis { .shared }

    /// Kaldırma: kurulu uygulamalar ve kalıntıları.
    public static var uninstall: UninstallService { .shared }

    /// Temizlik: önbellek, günlük, derleme çıktısı.
    public static var cleanup: CleanupService { .shared }

    /// Bakım işlemleri: DNS, Launch Services, Quick Look, Finder/Dock, Spotlight.
    public static var optimize: OptimizeService { .shared }

    /// Bayt sayısını kısa ve okunur biçime çevirir (1,2 GB).
    ///
    /// `ByteCountFormatter` yerine elle: biçimlendirici saniyede bir çağrıldığında
    /// ölçülebilir yük getiriyor ve burada gereken tek şey iki haneli bir sayı.
    public static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(value)
        var unit = 0
        while size >= 1024, unit < units.count - 1 {
            size /= 1024
            unit += 1
        }
        let decimals = (size < 10 && unit > 0) ? 1 : 0
        return String(format: "%.\(decimals)f %@", size, units[unit])
    }

    /// Saniyedeki bayt (3,4 MB/sn). Birim son eki çağıranın dilinden gelir.
    public static func rate(_ value: Double, perSecond: String) -> String {
        "\(bytes(UInt64(max(value, 0))))/\(perSecond)"
    }
}
