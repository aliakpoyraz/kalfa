import Combine
import Foundation

/// Disk analizinin arayüze bakan yüzü: taramayı başlatır, ilerlemeyi yayımlar,
/// biten ağaçta gezinmeyi tutar.
@MainActor
public final class DiskAnalysis: ObservableObject {

    public static let shared = DiskAnalysis()

    @Published public private(set) var progress = ScanProgress()
    @Published public private(set) var isScanning = false
    /// Taranan kök. Gezinme buradan başlar.
    @Published public private(set) var root: DiskNode?
    /// Kökten şu an bakılan dizine kadarki zincir; son eleman gösterilen dizin.
    @Published public private(set) var trail: [DiskNode] = []
    @Published public private(set) var lastError: String?

    private var scanner: Scanner?
    private let queue = DispatchQueue(label: "com.aliakpoyraz.kalfa.scanner", qos: .utility)

    private init() {}

    public var current: DiskNode? { trail.last ?? root }

    /// Varsayılan kök: ev dizini. Sistem birimi imzalı ve değiştirilemez, orayı
    /// taramak kullanıcıya silemeyeceği bir liste gösterirdi.
    public func start(root path: String = NSHomeDirectory()) {
        guard !isScanning else { return }
        guard Safety.mayScan(path) else {
            lastError = Safety.SafetyError.refused(path).localizedDescription
            return
        }

        isScanning = true
        lastError = nil
        progress = ScanProgress()
        root = nil
        trail = []

        let scanner = Scanner()
        self.scanner = scanner

        queue.async { [weak self] in
            let tree = scanner.scan(root: path) { snapshot in
                Task { @MainActor [weak self] in self?.progress = snapshot }
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                // İptal edilmiş tarama yarım ağaç döndürür; onu sonuç diye
                // göstermek kullanıcıya eksik tabloyu tam gibi sunmak olurdu.
                if self.isScanning {
                    self.root = tree
                    self.trail = [tree]
                }
                self.isScanning = false
                self.scanner = nil
            }
        }
    }

    public func cancel() {
        scanner?.cancel()
        isScanning = false
        scanner = nil
    }

    // MARK: Gezinme

    public func open(_ node: DiskNode) {
        guard node.isDirectory else { return }
        trail.append(node)
    }

    public func back() {
        guard trail.count > 1 else { return }
        trail.removeLast()
    }

    public func jump(to index: Int) {
        guard trail.indices.contains(index) else { return }
        trail = Array(trail.prefix(index + 1))
    }

    /// Gösterilen dizinin en büyük çocukları.
    public func rows(limit: Int = 40) -> [DiskNode] {
        current?.largestChildren(limit) ?? []
    }

    /// Bir satırın gösterilen dizin içindeki payı (0...1) — çubuk genişliği.
    public func share(of node: DiskNode) -> Double {
        guard let total = current?.size, total > 0 else { return 0 }
        return min(Double(node.size) / Double(total), 1)
    }

    // MARK: Çöpe taşıma

    /// Seçilen düğümü çöp kutusuna taşır ve ağacı günceller.
    ///
    /// Ağaç yeniden taranmaz: bir dizini çöpe atınca tüm taramayı tekrarlamak
    /// dakikalar sürerdi. Düğüm ağaçtan düşürülüp boyutu kök yönünde geri alınır.
    @discardableResult
    public func trash(_ node: DiskNode) -> Bool {
        do {
            try Safety.moveToTrash(URL(fileURLWithPath: node.path))
        } catch {
            lastError = error.localizedDescription
            return false
        }
        remove(node)
        return true
    }

    private func remove(_ node: DiskNode) {
        guard let root else { return }
        var stack = [root]
        while let parent = stack.popLast() {
            if let index = parent.children.firstIndex(where: { $0 === node }) {
                parent.children.remove(at: index)
                // Boyutu kökten bu düğüme kadar olan zincirden düş.
                for ancestor in trail where ancestor.size >= node.size {
                    ancestor.size &-= node.size
                    ancestor.fileCount -= node.fileCount
                }
                if root.size >= node.size, !trail.contains(where: { $0 === root }) {
                    root.size &-= node.size
                }
                objectWillChange.send()
                return
            }
            stack.append(contentsOf: parent.children.filter(\.isDirectory))
        }
    }
}
