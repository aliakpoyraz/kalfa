import Foundation

/// Uygulamanın diskteki tüm sabit konumları tek yerde.
///
/// Klasör adları `ezDPI` olarak kaldı: uygulama Kalfa içine taşındı ama
/// kullanıcının kural listesi, günlükleri ve kirli durum dosyası orada duruyor.
/// Adı güzelleştirmek için taşımak, mevcut kurulumun ayarını sıfırlamak demek.
enum Paths {
    /// ~/Library/Application Support/EzDPI
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ezDPI", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// ~/Library/Logs/ezDPI
    static let logs: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Logs/ezDPI", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let config = support.appendingPathComponent("config.json")
    /// Proxy açıkken tutulan kirli durum dosyası: uygulama çökerse bir sonraki
    /// açılışta sistem proxy'sini buradan geri koyarız.
    static let dirtyState = support.appendingPathComponent("proxy-state.json")

    static let appLog = logs.appendingPathComponent("ezdpi.log")

}
