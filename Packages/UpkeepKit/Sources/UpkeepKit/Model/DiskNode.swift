import Foundation

/// Taranmış bir dizin ya da dosya.
///
/// Sınıf, yapı değil: ağaç büyürken çocuklar ebeveynin boyutunu geriye doğru
/// güncelliyor ve değer tipiyle bu her adımda tüm alt ağacı kopyalamak olurdu.
public final class DiskNode: @unchecked Sendable {
    public let name: String
    public let path: String
    public let isDirectory: Bool
    /// Diskte gerçekten tutulan bayt (`st_blocks × 512`), görünen dosya boyutu
    /// değil. Seyrek dosyalar ve APFS klonları ikisinin arasını açar; kullanıcı
    /// "ne kadar yer açılır" diye sorarken diskteki karşılığı kastediyor.
    public internal(set) var size: UInt64
    public internal(set) var fileCount: Int
    public internal(set) var children: [DiskNode]

    init(name: String, path: String, isDirectory: Bool, size: UInt64 = 0) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.fileCount = isDirectory ? 0 : 1
        self.children = []
    }

    /// Büyükten küçüğe, yalnızca ilk `limit` çocuk. Bir dizinde on bin girdi
    /// olabiliyor; hepsini çizmek listeyi okunmaz yapar.
    public func largestChildren(_ limit: Int = 30) -> [DiskNode] {
        Array(children.sorted { $0.size > $1.size }.prefix(limit))
    }
}

/// Tarama ilerlemesi. Arayüz bunu saniyede birkaç kez okur.
public struct ScanProgress: Sendable, Equatable {
    public var scannedFiles: Int = 0
    public var scannedBytes: UInt64 = 0
    /// Şu an hangi dizinde olunduğu; kullanıcı taramanın takılmadığını görsün.
    public var currentPath: String = ""
    public var isFinished: Bool = false
    public init() {}
}
