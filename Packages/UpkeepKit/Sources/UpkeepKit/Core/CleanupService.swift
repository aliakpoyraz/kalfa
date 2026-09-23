import Combine
import Foundation

/// Temizlik akışı: tara, seç, onayla, çöpe taşı.
@MainActor
public final class CleanupService: ObservableObject {

    public static let shared = CleanupService()

    @Published public private(set) var items: [CleanupItem] = []
    @Published public private(set) var isScanning = false
    @Published public var checked: Set<String> = []
    @Published public private(set) var lastResult: String?
    @Published public private(set) var lastError: String?

    private let queue = DispatchQueue(label: "com.aliakpoyraz.kalfa.cleanup", qos: .utility)

    private init() {}

    public func scan() {
        guard !isScanning else { return }
        isScanning = true
        lastError = nil
        lastResult = nil

        queue.async { [weak self] in
            let found = Sweeper.scan()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.items = found
                // Yalnızca yeniden üretilebilenler işaretli gelir. Kurulum
                // dosyaları, cihaz destekleri ve proje çıktıları kullanıcının
                // saklamak isteyebileceği şeyler — onları araç seçmez.
                self.checked = Set(found.filter(\.recommended).map(\.path))
                self.isScanning = false
            }
        }
    }

    public func toggle(_ item: CleanupItem) {
        if checked.contains(item.path) {
            checked.remove(item.path)
        } else {
            checked.insert(item.path)
        }
    }

    public func toggleCategory(_ category: CleanupItem.Category) {
        let paths = items.filter { $0.category == category }.map(\.path)
        let allOn = paths.allSatisfy { checked.contains($0) }
        for path in paths {
            if allOn { checked.remove(path) } else { checked.insert(path) }
        }
    }

    public func items(in category: CleanupItem.Category) -> [CleanupItem] {
        items.filter { $0.category == category }
    }

    public var categories: [CleanupItem.Category] {
        CleanupItem.Category.allCases.filter { category in
            items.contains { $0.category == category }
        }
    }

    public var checkedSize: UInt64 {
        items.filter { checked.contains($0.path) }.reduce(0) { $0 &+ $1.size }
    }

    public var checkedCount: Int { checked.count }

    /// Seçilenleri çöp kutusuna taşır.
    ///
    /// Çöp kutusunun kendisi seçilmişse içi boşaltılır — bir klasörü kendi
    /// içine taşımak mümkün değil.
    public func clean() {
        let targets = items.filter { checked.contains($0.path) }
        guard !targets.isEmpty else { return }

        var moved = 0
        var freed: UInt64 = 0
        var failures: [String] = []

        for item in targets {
            if item.category == .trash {
                emptyTrash(item, moved: &moved, freed: &freed, failures: &failures)
                continue
            }
            do {
                try Safety.moveToTrash(URL(fileURLWithPath: item.path))
                moved += 1
                freed &+= item.size
            } catch {
                failures.append(item.displayName)
            }
        }

        lastResult = "\(moved) öğe · \(Upkeep.bytes(freed))"
        lastError = failures.isEmpty ? nil : "Dokunulamadı: \(failures.prefix(3).joined(separator: ", "))"
        checked = []
        scan()
    }

    private func emptyTrash(_ item: CleanupItem,
                            moved: inout Int,
                            freed: inout UInt64,
                            failures: inout [String]) {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(atPath: item.path) else {
            failures.append(item.displayName)
            return
        }
        for entry in entries {
            do {
                try manager.removeItem(atPath: "\(item.path)/\(entry)")
                moved += 1
            } catch {
                failures.append(entry)
            }
        }
        freed &+= item.size
    }
}
