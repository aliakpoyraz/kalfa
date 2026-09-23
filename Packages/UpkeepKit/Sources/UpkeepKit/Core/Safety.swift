import Foundation

/// Neye dokunulabileceğine karar veren tek yer.
///
/// Tarayıcı da temizlikçi de kaldırıcı da buradan geçer. Kural listesi üç ayrı
/// dosyaya dağılsaydı biri güncellenip diğeri unutulurdu ve unutulan taraf
/// kullanıcının verisini silerdi.
public enum Safety {

    /// Hiçbir koşulda içine girilmeyen kökler.
    ///
    /// `/System` ve `/usr` imzalı sistem birimidir — okumak bile boşuna zaman.
    /// `/Volumes` başka disklerdir: kullanıcı "Mac'imde ne yer kaplıyor" diye
    /// sorarken bağlı yedek diskini kastetmiyor, üstelik ağ birimini taramak
    /// dakikalar sürer.
    public static let forbiddenRoots: Set<String> = [
        "/System", "/usr", "/bin", "/sbin", "/private/var/db",
        "/Library/Apple", "/Volumes", "/net", "/dev", "/.vol"
    ]

    /// Silme önerisi ASLA üretilmeyen yerler. Taranırlar — ne kapladıkları
    /// gösterilir — ama temizlik adayı olamazlar.
    ///
    /// Kullanıcının belgeleri buradadır. Bir temizlik aracının "Masaüstü 40 GB,
    /// silelim mi" demesi, aracın kendisinin zarar olduğu andır.
    public static var neverDelete: Set<String> {
        let home = NSHomeDirectory()
        return [
            home,
            "\(home)/Documents", "\(home)/Desktop", "\(home)/Downloads",
            "\(home)/Pictures", "\(home)/Movies", "\(home)/Music",
            "\(home)/Library", "\(home)/Library/Mobile Documents",
            "/Applications", "/Users", "/Library"
        ]
    }

    /// Yol taranabilir mi?
    public static func mayScan(_ path: String) -> Bool {
        !forbiddenRoots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// Yol silme adayı olabilir mi?
    ///
    /// Üç kapı: yasak kökte olmayacak, korunan dizinin KENDİSİ olmayacak (içi
    /// olabilir — `~/Library/Caches/X` silinebilir, `~/Library` silinemez) ve
    /// ev dizininin altında kalacak.
    public static func mayDelete(_ path: String) -> Bool {
        let clean = (path as NSString).standardizingPath
        guard mayScan(clean) else { return false }
        guard !neverDelete.contains(clean) else { return false }
        // Ev dizini dışına çıkan aday kabul edilmez. Sistem genelinde temizlik
        // yönetici hakkı ister ve bu uygulama onu istemiyor.
        return clean.hasPrefix(NSHomeDirectory() + "/")
    }

    /// Uygulama paketi kaldırılabilir mi?
    ///
    /// `mayDelete` bilerek ev dizinine kapalı, ama kaldırma işinin konusu tam
    /// da `/Applications` içindeki paket. Bu yüzden ayrı bir kapı: yalnızca
    /// `.app` ile biten, uygulama klasörlerinin DOĞRUDAN çocuğu olan yollar.
    /// `/System/Applications` zaten yasak köklerde — Apple'ın uygulamaları
    /// buraya hiç düşmez.
    public static func mayDeleteApp(_ path: String) -> Bool {
        let clean = (path as NSString).standardizingPath
        guard clean.hasSuffix(".app"), mayScan(clean) else { return false }
        let parent = (clean as NSString).deletingLastPathComponent
        return parent == "/Applications"
            || parent == "\(NSHomeDirectory())/Applications"
            || parent.hasPrefix("/Applications/")
    }

    /// Yol kullanıcının kendi çöp kutusu mu?
    ///
    /// Çöp kutusunu boşaltmak kalıcıdır ve bu modüldeki tek geri alınamaz
    /// işlemdir. Onu çalıştıran tek yer buradan geçer, yani "kalıcı silme"
    /// kapısı da tek noktada durur.
    public static func isTrash(_ path: String) -> Bool {
        (path as NSString).standardizingPath == "\(NSHomeDirectory())/.Trash"
    }

    /// Silmek yerine çöp kutusuna taşır.
    ///
    /// Geri alınamayan bir işlemi varsayılan yapmıyoruz: bir temizlik aracının
    /// yanlış dosyayı seçmesi mümkün, kullanıcının onu geri alamaması kabul
    /// edilemez. Çöp kutusu zaten kullanıcının bildiği geri alma yolu.
    ///
    /// - Parameter allowingApps: kaldırma akışı için `/Applications` içindeki
    ///   paketlere de izin verir. Varsayılan kapalı: disk analizindeki bir
    ///   yanlış tık uygulamaları uçurmasın.
    @discardableResult
    public static func moveToTrash(_ url: URL, allowingApps: Bool = false) throws -> URL? {
        let permitted = mayDelete(url.path) || (allowingApps && mayDeleteApp(url.path))
        guard permitted else { throw SafetyError.refused(url.path) }
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }

    public enum SafetyError: LocalizedError {
        case refused(String)

        public var errorDescription: String? {
            switch self {
            case .refused(let path):
                return "Korunan yol, dokunulmadı: \(path)"
            }
        }
    }
}
