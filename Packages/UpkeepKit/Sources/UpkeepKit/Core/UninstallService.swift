import AppKit
import Combine
import Foundation

/// Kaldırma akışı: uygulamayı seç, ne gideceğini gör, onayla.
///
/// Akış bilerek iki adımlı. Tek tıkla kaldıran bir araç, kullanıcının
/// beklemediği bir dosyayı da götürdüğünde bunu ancak sonradan fark ettirir.
@MainActor
public final class UninstallService: ObservableObject {

    public static let shared = UninstallService()

    @Published public private(set) var apps: [InstalledApp] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var selected: InstalledApp?
    @Published public private(set) var leftovers: [Leftover] = []
    /// Kullanıcının kaldırmayı onayladığı yollar. Varsayılan olarak yalnızca
    /// kaldırılabilir olanlar işaretli gelir; kullanıcı tek tek kaldırabilir.
    @Published public var checked: Set<String> = []
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastResult: String?

    private let queue = DispatchQueue(label: "com.aliakpoyraz.kalfa.uninstall", qos: .userInitiated)

    private init() {}

    // MARK: Liste

    public func loadApps() {
        guard !isLoading else { return }
        isLoading = true
        lastError = nil

        queue.async { [weak self] in
            let found = Uninstaller.installedApps()
            Task { @MainActor [weak self] in
                self?.apps = found
                self?.isLoading = false
            }
        }
    }

    // MARK: Seçim

    public func select(_ app: InstalledApp) {
        selected = app
        leftovers = []
        checked = []
        lastResult = nil

        queue.async { [weak self] in
            let found = Uninstaller.leftovers(for: app)
            Task { @MainActor [weak self] in
                guard let self, self.selected?.path == app.path else { return }
                self.leftovers = found.sorted { $0.size > $1.size }
                self.checked = Set(found.filter(\.isRemovable).map(\.path))
            }
        }
    }

    public func clearSelection() {
        selected = nil
        leftovers = []
        checked = []
    }

    public func toggle(_ leftover: Leftover) {
        guard leftover.isRemovable else { return }
        if checked.contains(leftover.path) {
            checked.remove(leftover.path)
        } else {
            checked.insert(leftover.path)
        }
    }

    /// Onaylanmış seçimin toplam boyutu — onay metninde gösterilir.
    public var checkedSize: UInt64 {
        leftovers.filter { checked.contains($0.path) }.reduce(0) { $0 &+ $1.size }
    }

    public var checkedCount: Int { checked.count }

    // MARK: Uygulama

    /// Seçilenleri çöp kutusuna taşır.
    ///
    /// Uygulama açıksa iş yapılmaz: çalışan bir uygulamanın paketini çöpe atmak
    /// onu yarı silinmiş bir hâlde bırakır ve kapanırken dosyalarını geri yazar.
    public func uninstall() {
        guard let app = selected else { return }
        if NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty == false {
            lastError = "\(app.name) açık. Önce kapat, sonra kaldır."
            return
        }

        let targets = leftovers.filter { checked.contains($0.path) && $0.isRemovable }
        guard !targets.isEmpty else { return }

        var moved = 0
        var freed: UInt64 = 0
        var failures: [String] = []

        for leftover in targets {
            do {
                try Safety.moveToTrash(URL(fileURLWithPath: leftover.path), allowingApps: true)
                moved += 1
                freed &+= leftover.size
            } catch {
                failures.append((leftover.path as NSString).lastPathComponent)
            }
        }

        lastResult = "\(moved) öğe çöp kutusuna taşındı · \(Upkeep.bytes(freed))"
        lastError = failures.isEmpty ? nil : "Taşınamadı: \(failures.joined(separator: ", "))"

        // Liste artık gerçeği yansıtmıyor; taze çek.
        clearSelection()
        loadApps()
    }
}
