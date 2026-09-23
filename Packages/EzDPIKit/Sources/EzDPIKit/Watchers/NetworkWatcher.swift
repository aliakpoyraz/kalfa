import Foundation
import Network
import CoreWLAN

/// Ağ değişikliklerini izler ve mevcut Wi-Fi adını verir.
/// SSID okumak macOS 14'ten beri konum iznine bağlı; izin yoksa nil döner ve
/// kural yalnızca ağ servisi adına göre eşleşir.
@MainActor
final class NetworkWatcher {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.aliakpoyraz.ezdpi.network")
    private(set) var currentSSID: String?
    private(set) var activeServices: [String] = []
    private var onChange: () -> Void = {}

    func start(onChange: @escaping () -> Void) {
        self.onChange = onChange
        refresh()
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.onChange()
            }
        }
        monitor.start(queue: queue)
    }

    func refresh() {
        currentSSID = Self.readSSID()
        activeServices = SystemProxyController.activeServices()
    }

    static func readSSID() -> String? {
        if let ssid = CWWiFiClient.shared().interface()?.ssid(), !ssid.isEmpty {
            return ssid
        }
        // CoreWLAN izin yokken nil döner; komut satırı karşılığını da deneriz.
        guard let iface = CWWiFiClient.shared().interface()?.interfaceName else { return nil }
        let result = Shell.run("/usr/sbin/networksetup", ["-getairportnetwork", iface], timeout: 5)
        guard result.ok, let range = result.stdout.range(of: "Current Wi-Fi Network: ") else { return nil }
        let name = String(result.stdout[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Konum izni olmadan SSID okunamıyorsa arayüz bunu kullanıcıya söyler.
    var ssidReadable: Bool { currentSSID != nil }
}
