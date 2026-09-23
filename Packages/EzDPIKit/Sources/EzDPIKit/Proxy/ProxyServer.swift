import Foundation
import Network

/// The listener on 127.0.0.1 that the system proxy setting points at.
///
/// It holds the rule table, so deciding what to do with a host is a dictionary
/// lookup in this process rather than a config file written out for someone
/// else's binary to read at startup. That is what makes a rule change take
/// effect without restarting anything.
final class ProxyServer: @unchecked Sendable {

    struct Rule {
        let domains: [String]
        let mode: SplitMode
        let chunkSize: Int
        let dns: DNSMode
        let name: String
        let priority: Int
    }

    private let queue = DispatchQueue(label: "com.aliakpoyraz.kalfa.proxy", attributes: .concurrent)
    private let lock = NSLock()
    private var rules: [Rule] = []
    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: ProxySession] = [:]

    private(set) var port: UInt16 = 0

    var onFailure: ((String) -> Void)?

    // MARK: Lifecycle

    func start(host: String, port: UInt16, rules: [Rule]) throws {
        setRules(rules)

        let options = NWProtocolTCP.Options()
        options.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: options)
        parameters.allowLocalEndpointReuse = true
        // Loopback only. A DPI helper listening on every interface is an open
        // proxy for whoever else is on the café Wi-Fi.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? 18080
        )

        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .failed(let error) = state {
                // The engine dying used to mean a child process exited; now it
                // means the listener gave up. The supervisor treats both the
                // same way: put the system proxy back immediately.
                self.onFailure?(error.localizedDescription)
            }
        }
        listener.start(queue: queue)
        self.listener = listener
        self.port = port
        Log.write(.info, "Yerel motor dinlemede: \(host):\(port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        lock.lock()
        let open = sessions.values
        sessions.removeAll()
        lock.unlock()
        for session in open { session.cancel() }
        Log.write(.info, "Yerel motor durduruldu.")
    }

    var isRunning: Bool { listener != nil }

    // MARK: Rules

    /// Swapped under the lock while connections are live: an existing tunnel
    /// keeps the decision it started with, and the next one gets the new table.
    func setRules(_ rules: [Rule]) {
        lock.lock()
        self.rules = rules.sorted { $0.priority > $1.priority }
        lock.unlock()
    }

    private func decision(for host: String) -> ProxySession.Decision {
        lock.lock()
        let table = rules
        lock.unlock()

        for rule in table where rule.domains.contains(where: { matches(host: host, pattern: $0) }) {
            return ProxySession.Decision(mode: rule.mode,
                                         chunkSize: rule.chunkSize,
                                         dns: rule.dns,
                                         ruleName: rule.name)
        }
        return .passthrough
    }

    /// `discord.com` covers `discord.com` and anything under it; a pattern the
    /// person wrote with a star is honoured as written.
    private func matches(host: String, pattern: String) -> Bool {
        let pattern = pattern.lowercased()
        if pattern.hasPrefix("*.") || pattern.hasPrefix("**.") {
            let base = pattern.drop(while: { $0 == "*" || $0 == "." })
            return host == base || host.hasSuffix(".\(base)")
        }
        return host == pattern || host.hasSuffix(".\(pattern)")
    }

    // MARK: Connections

    private func accept(_ connection: NWConnection) {
        let session = ProxySession(client: connection, queue: queue) { [weak self] host in
            self?.decision(for: host) ?? .passthrough
        }
        let key = ObjectIdentifier(session)
        lock.lock()
        sessions[key] = session
        lock.unlock()

        session.onFinish = { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.sessions.removeValue(forKey: key)
            self.lock.unlock()
        }
        session.start()
    }

    /// Whether anything is already listening there.
    ///
    /// Asked by trying to bind rather than by shelling out to `lsof`: the answer
    /// is the same one the listener would give, and it costs no process.
    static func isPortBusy(host: String, port: UInt16) -> Bool {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? 18080
        )
        guard let probe = try? NWListener(using: parameters) else { return true }
        probe.cancel()
        return false
    }
}
