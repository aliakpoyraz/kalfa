import AppKit
import Foundation

/// Uygulamayı ve geride bıraktıklarını bulur.
///
/// Paketi çöpe atmak macOS'un öğrettiği yol ama eksik: uygulama ayarlarını,
/// önbelleğini, kabını ve kendi LaunchAgent'ını geride bırakır. Bu sınıf onları
/// paket kimliği ve uygulama adıyla eşler.
public enum Uninstaller {

    // MARK: Kurulu uygulamalar

    /// `/Applications`, `~/Applications` ve bunların bir alt klasörü.
    ///
    /// Bir alt seviye yeterli: Apple'ın `Utilities` klasörü ve insanların
    /// kurduğu "Adobe", "Microsoft" gibi gruplar orada duruyor. Daha derine
    /// inmek uygulama paketlerinin İÇİNDEKİ yardımcı uygulamaları listelerdi.
    public static func installedApps() -> [InstalledApp] {
        let roots = ["/Applications", "\(NSHomeDirectory())/Applications"]
        let manager = FileManager.default
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))

        var apps: [InstalledApp] = []
        var seen = Set<String>()

        for root in roots {
            guard let entries = try? manager.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries {
                let path = "\(root)/\(entry)"
                if entry.hasSuffix(".app") {
                    if let app = describe(path: path, running: running), seen.insert(path).inserted {
                        apps.append(app)
                    }
                    continue
                }
                // Grup klasörü: bir seviye daha bak.
                var isDirectory: ObjCBool = false
                guard manager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
                      let inner = try? manager.contentsOfDirectory(atPath: path) else { continue }
                for child in inner where child.hasSuffix(".app") {
                    let childPath = "\(path)/\(child)"
                    if let app = describe(path: childPath, running: running), seen.insert(childPath).inserted {
                        apps.append(app)
                    }
                }
            }
        }
        return apps.sorted { $0.size > $1.size }
    }

    private static func describe(path: String, running: Set<String>) -> InstalledApp? {
        guard let bundle = Bundle(path: path), let bundleID = bundle.bundleIdentifier else { return nil }
        let name = (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        let scanner = Scanner()
        let size = scanner.scan(root: path) { _ in }.size
        return InstalledApp(name: name,
                            path: path,
                            bundleID: bundleID,
                            size: size,
                            isRunning: running.contains(bundleID))
    }

    // MARK: Kalıntılar

    /// Uygulamanın kendisi + geride bıraktıkları.
    ///
    /// Eşleme paket kimliği üzerinden yapılır, isim üzerinden DEĞİL. "Notes"
    /// adına göre eşlemek `~/Library/Application Support/Notes` altında başka
    /// bir aracın verisini yakalayabilirdi; paket kimliği tekil.
    public static func leftovers(for app: InstalledApp) -> [Leftover] {
        let home = NSHomeDirectory()
        let bundleID = app.bundleID

        var found: [Leftover] = [
            Leftover(path: app.path, size: app.size, kind: .bundle,
                     isRemovable: Safety.mayDeleteApp(app.path))
        ]

        /// Paket kimliğiyle birebir eşleşen sabit konumlar.
        let exact: [(String, Leftover.Kind)] = [
            ("\(home)/Library/Application Support/\(bundleID)", .support),
            ("\(home)/Library/Caches/\(bundleID)", .caches),
            ("\(home)/Library/Preferences/\(bundleID).plist", .preferences),
            ("\(home)/Library/Containers/\(bundleID)", .container),
            ("\(home)/Library/Saved Application State/\(bundleID).savedState", .savedState),
            ("\(home)/Library/HTTPStorages/\(bundleID)", .webData),
            ("\(home)/Library/WebKit/\(bundleID)", .webData),
            ("\(home)/Library/Application Scripts/\(bundleID)", .scripts),
            ("\(home)/Library/Logs/\(bundleID)", .logs),
            // Uygulama adıyla açılan destek klasörü: paket kimliğini kullanmayan
            // uygulamalar (çoğu Electron ve oyun) verisini buraya koyuyor.
            ("\(home)/Library/Application Support/\(app.name)", .support),
            ("\(home)/Library/Logs/\(app.name)", .logs)
        ]

        for (path, kind) in exact where FileManager.default.fileExists(atPath: path) {
            found.append(describe(path: path, kind: kind))
        }

        // Kimliği İÇEREN dosyalar: ByHost tercihleri, grup kapları, LaunchAgent'lar.
        found += matching(in: "\(home)/Library/Preferences/ByHost", contains: bundleID, kind: .preferences)
        found += matching(in: "\(home)/Library/Group Containers", contains: bundleID, kind: .container)
        found += matching(in: "\(home)/Library/LaunchAgents", contains: bundleID, kind: .launchAgent)
        // Sistem geneli olanlar yönetici hakkı ister; gösterilir, seçilemez.
        found += matching(in: "/Library/LaunchAgents", contains: bundleID, kind: .launchAgent)
        found += matching(in: "/Library/LaunchDaemons", contains: bundleID, kind: .launchAgent)

        var seen = Set<String>()
        return found.filter { seen.insert($0.path).inserted }
    }

    private static func matching(in directory: String, contains needle: String, kind: Leftover.Kind) -> [Leftover] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        // Kimliğin son parçası da aranır: grup kapları çoğunlukla takım
        // kimliğiyle öne eklenmiş hâlde duruyor (`ABCDE12345.com.firma.uygulama`).
        let tail = needle.split(separator: ".").last.map(String.init) ?? needle
        return entries
            .filter { $0.contains(needle) || ($0.contains(tail) && tail.count > 4) }
            .map { describe(path: "\(directory)/\($0)", kind: kind) }
    }

    private static func describe(path: String, kind: Leftover.Kind) -> Leftover {
        var size: UInt64 = 0
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                size = Scanner().scan(root: path) { _ in }.size
            } else if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                      let bytes = attributes[.size] as? UInt64 {
                size = bytes
            }
        }
        return Leftover(path: path, size: size, kind: kind,
                        isRemovable: Safety.mayDelete(path))
    }
}
