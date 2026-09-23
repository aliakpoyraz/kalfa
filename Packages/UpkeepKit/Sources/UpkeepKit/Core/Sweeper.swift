import Darwin
import Foundation

/// Temizlik adaylarını bulur. Hiçbir şeyi silmez — bulur, ölçer, döndürür.
///
/// Bulmakla silmek bilerek ayrı: kullanıcı önce listeyi görür. "Kuru çalıştırma"
/// bu aracın varsayılanı değil, tek çalışma biçimi; silme ancak kullanıcı
/// listeden seçip onayladığında olur.
public enum Sweeper {

    /// İçine girilmeyen proje klasörü adları. Eşleşen dizin ADAY olur, içine
    /// inilmez: `node_modules` içinde başka `node_modules`'lar var ve her birini
    /// ayrı aday yapmak listeyi binlerce satıra çıkarırdı.
    private static let artifactNames: Set<String> = [
        "node_modules", ".next", "dist", "build", ".build", "target",
        "Pods", "__pycache__", ".venv", "venv", ".gradle", ".parcel-cache",
        ".turbo", "DerivedData", ".pytest_cache", ".mypy_cache"
    ]

    /// Kurulum dosyası uzantıları.
    private static let installerExtensions: Set<String> = ["dmg", "pkg", "iso", "xip"]

    /// Proje aramasının ineceği en fazla derinlik.
    ///
    /// Sınırsız arama tüm ev dizinini bir kez daha yürümek demek. Altı seviye
    /// insanların kodu tuttuğu her yeri kapsıyor (`~/işler/müşteri/proje/...`)
    /// ve aramayı saniyeler içinde bitiriyor.
    private static let artifactDepth = 6

    // MARK: Tarama

    public static func scan() -> [CleanupItem] {
        var items: [CleanupItem] = []
        items += systemJunk()
        items += developerJunk()
        items += installers()
        items += projectArtifacts()
        items += trash()
        return items.filter { $0.size > 0 }.sorted { $0.size > $1.size }
    }

    // MARK: Kategoriler

    private static func systemJunk() -> [CleanupItem] {
        let home = NSHomeDirectory()
        var items: [CleanupItem] = []

        // Önbellek ve günlükler: uygulamalar bunları yeniden üretir.
        items += children(of: "\(home)/Library/Caches", category: .caches, recommended: true)
        items += children(of: "\(home)/Library/Logs", category: .logs, recommended: true)
        // Kaydedilmiş pencere durumu: silinince uygulamalar pencerelerini
        // hatırlamaz, veri kaybı yok.
        items += children(of: "\(home)/Library/Saved Application State",
                          category: .savedState, recommended: true)
        items += children(of: "\(home)/Library/Logs/DiagnosticReports",
                          category: .crashReports, recommended: true)
        return items
    }

    private static func developerJunk() -> [CleanupItem] {
        let developer = "\(NSHomeDirectory())/Library/Developer"
        var items: [CleanupItem] = []

        // Xcode türetilmiş veri: tamamen yeniden üretilebilir.
        items += children(of: "\(developer)/Xcode/DerivedData",
                          category: .derivedData, recommended: true)
        // Cihaz destek dosyaları: yeniden indirilir ama cihaz bağlamak gerekir,
        // bu yüzden işaretsiz gelir.
        items += children(of: "\(developer)/Xcode/iOS DeviceSupport",
                          category: .deviceSupport, recommended: false)
        items += children(of: "\(developer)/CoreSimulator/Caches",
                          category: .simulator, recommended: true)
        return items
    }

    /// İndirilenler klasöründeki kurulum dosyaları. Uygulama kurulduktan sonra
    /// disk imajının durması için bir sebep yok, ama kullanıcının sakladığı bir
    /// sürüm olabilir — işaretsiz gelirler.
    private static func installers() -> [CleanupItem] {
        let downloads = "\(NSHomeDirectory())/Downloads"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: downloads) else { return [] }

        return entries.compactMap { entry in
            let ext = (entry as NSString).pathExtension.lowercased()
            guard installerExtensions.contains(ext) else { return nil }
            let path = "\(downloads)/\(entry)"
            guard let size = fileSize(path) else { return nil }
            return CleanupItem(path: path, displayName: entry, size: size,
                               category: .installers, recommended: false)
        }
    }

    /// Ev dizininde derleme çıktısı klasörleri.
    private static func projectArtifacts() -> [CleanupItem] {
        var items: [CleanupItem] = []
        find(in: NSHomeDirectory(), depth: 0, into: &items)
        return items
    }

    private static func find(in path: String, depth: Int, into items: inout [CleanupItem]) {
        guard depth < artifactDepth, Safety.mayScan(path) else { return }
        guard let directory = opendir(path) else { return }
        defer { closedir(directory) }
        let descriptor = dirfd(directory)

        while let entry = readdir(directory) {
            var raw = entry.pointee.d_name
            let name = withUnsafePointer(to: &raw) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
            }
            guard name != ".", name != ".." else { continue }

            var status = stat()
            guard fstatat(descriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0,
                  (status.st_mode & S_IFMT) == S_IFDIR else { continue }

            let childPath = "\(path)/\(name)"
            if artifactNames.contains(name) {
                // Eşleşti: ölç ve İÇİNE GİRME.
                let size = Scanner().scan(root: childPath) { _ in }.size
                items.append(CleanupItem(path: childPath,
                                         displayName: shortPath(childPath),
                                         size: size,
                                         category: .projectArtifacts,
                                         recommended: false))
                continue
            }
            // Kütüphane ve gizli sistem klasörleri proje değil; oraya inmek
            // aramayı yavaşlatır ve yanlış eşleşme üretir.
            guard name != "Library", childPath != "\(NSHomeDirectory())/Library" else { continue }
            find(in: childPath, depth: depth + 1, into: &items)
        }
    }

    private static func trash() -> [CleanupItem] {
        let path = "\(NSHomeDirectory())/.Trash"
        let size = Scanner().scan(root: path) { _ in }.size
        guard size > 0 else { return [] }
        // Çöp kutusunun kendisi çöpe taşınamaz; arayüz bunu ayrı ele alır.
        // Görünen ad arayüzün diline bırakılıyor; modül metin taşımıyor.
        return [CleanupItem(path: path, displayName: ".Trash", size: size,
                            category: .trash, recommended: false)]
    }

    // MARK: Yardımcılar

    private static func children(of directory: String,
                                 category: CleanupItem.Category,
                                 recommended: Bool) -> [CleanupItem] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        return entries.compactMap { entry in
            let path = "\(directory)/\(entry)"
            guard Safety.mayDelete(path) else { return nil }
            let size = Scanner().scan(root: path) { _ in }.size
            let direct = fileSize(path) ?? 0
            let total = max(size, direct)
            guard total > 0 else { return nil }
            return CleanupItem(path: path, displayName: entry, size: total,
                               category: category, recommended: recommended)
        }
    }

    private static func fileSize(_ path: String) -> UInt64? {
        var status = stat()
        guard lstat(path, &status) == 0 else { return nil }
        return UInt64(max(status.st_blocks, 0)) * 512
    }

    /// Ev dizini kökünü `~` ile kısaltır; tam yol listede okunmuyor.
    private static func shortPath(_ path: String) -> String {
        path.hasPrefix(NSHomeDirectory())
            ? "~" + path.dropFirst(NSHomeDirectory().count)
            : path
    }
}
