import Foundation
import Observation

/// DNS switching and "eject everything".
///
/// DNS goes through `networksetup`, the same tool the DPI half drives for the
/// proxy — it needs no administrator rights for this, and it writes to the same
/// place System Settings does, so nothing here is a private back door.
@MainActor
@Observable
final class NetworkTools {

    static let shared = NetworkTools()

    enum DNSChoice: String, CaseIterable, Identifiable {
        case automatic
        case cloudflare
        case google
        case quad9

        var id: String { rawValue }

        /// `nil` hands the decision back to DHCP.
        var servers: [String]? {
            switch self {
            case .automatic: return nil
            case .cloudflare: return ["1.1.1.1", "1.0.0.1"]
            case .google: return ["8.8.8.8", "8.8.4.4"]
            case .quad9: return ["9.9.9.9", "149.112.112.112"]
            }
        }

        var label: String {
            switch self {
            case .automatic: return L10n.t("dns.automatic")
            case .cloudflare: return "Cloudflare"
            case .google: return "Google"
            case .quad9: return "Quad9"
            }
        }
    }

    private(set) var dns: DNSChoice = .automatic
    private(set) var dnsDetail: String = ""

    private init() {
        refreshDNS()
    }

    // MARK: DNS

    func refreshDNS() {
        let services = activeServices()
        guard let first = services.first else {
            dns = .automatic
            dnsDetail = ""
            return
        }
        let output = Shell.result("/usr/sbin/networksetup", ["-getdnsservers", first])
        let servers = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.first?.isNumber == true }

        dns = DNSChoice.allCases.first { $0.servers == servers } ?? (servers.isEmpty ? .automatic : .automatic)
        dnsDetail = servers.isEmpty ? L10n.t("dns.fromRouter") : servers.joined(separator: ", ")
    }

    /// Applies to every service that is actually up, so the setting survives
    /// moving between Wi-Fi and a cable the way the proxy already does.
    func setDNS(_ choice: DNSChoice) {
        for service in activeServices() {
            let arguments = ["-setdnsservers", service] + (choice.servers ?? ["empty"])
            _ = Shell.result("/usr/sbin/networksetup", arguments)
        }
        dns = choice
        refreshDNS()
    }

    /// Only the services with a working connection; setting DNS on a disconnected
    /// one succeeds silently and then surprises the next time it comes up.
    private func activeServices() -> [String] {
        let listing = Shell.result("/usr/sbin/networksetup", ["-listallnetworkservices"])
        let names = listing
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.hasPrefix("An asterisk") && !$0.hasPrefix("*") }

        return names.filter { service in
            let info = Shell.result("/usr/sbin/networksetup", ["-getinfo", service])
            return info.contains("IP address:") && !info.contains("IP address: none")
        }
    }
}

/// Small wrapper so the tools above read as one line each.
enum Shell {
    static func result(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
