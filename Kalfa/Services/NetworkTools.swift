import Foundation
import Observation
import KalfaUI

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

    /// Nothing is read here. The first use of `shared` is usually a view being
    /// built, and that is no place to run four `networksetup` commands; the page
    /// asks for a refresh once it is on screen.
    private init() {}

    // MARK: DNS

    /// Reads the current DNS off the main thread and publishes it when it is in.
    func refreshDNS() {
        Task {
            let (choice, detail) = await Task.detached { Self.readDNS() }.value
            dns = choice
            dnsDetail = detail
        }
    }

    private nonisolated static func readDNS() -> (DNSChoice, String) {
        guard let first = activeServices().first else { return (.automatic, "") }
        let output = Shell.result("/usr/sbin/networksetup", ["-getdnsservers", first])
        let servers = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.first?.isNumber == true }

        let choice = DNSChoice.allCases.first { $0.servers == servers } ?? .automatic
        return (choice, servers.isEmpty ? L10n.t("dns.fromRouter") : servers.joined(separator: ", "))
    }

    /// Applies to every service that is actually up, so the setting survives
    /// moving between Wi-Fi and a cable the way the proxy already does.
    func setDNS(_ choice: DNSChoice) {
        // Shown at once; the commands run behind it and the read-back corrects
        // the picker if any of them did not take.
        dns = choice
        Task {
            await Task.detached {
                for service in Self.activeServices() {
                    let arguments = ["-setdnsservers", service] + (choice.servers ?? ["empty"])
                    _ = Shell.result("/usr/sbin/networksetup", arguments)
                }
            }.value
            refreshDNS()
        }
    }

    /// Only the services with a working connection; setting DNS on a disconnected
    /// one succeeds silently and then surprises the next time it comes up.
    private nonisolated static func activeServices() -> [String] {
        let listing = Shell.result("/usr/sbin/networksetup", ["-listallnetworkservices"])
        let names = listing
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.hasPrefix("An asterisk") && !$0.hasPrefix("*") }

        return names.filter { service in
            let info = Shell.result("/usr/sbin/networksetup", ["-getinfo", service])
            // The line has to *start* with it. Searching the whole text also
            // matched "IPv6 IP address: none", which every IPv4-only network
            // prints, and so counted a working Wi-Fi as disconnected.
            return info.split(whereSeparator: \.isNewline).contains { line in
                line.hasPrefix("IP address: ") && line != "IP address: none"
            }
        }
    }
}
