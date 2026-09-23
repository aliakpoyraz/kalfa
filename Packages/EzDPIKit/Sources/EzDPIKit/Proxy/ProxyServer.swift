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

    /// Binds and waits until the listener is actually up.
    ///
    /// This has to be async. `NWListener.start` returns immediately and reports
    /// success or failure later on its own queue, so a synchronous version could
    /// only ever mean "asked politely". The supervisor turns the system proxy on
    /// the moment this returns; if it returned before the bind was decided, a
    /// failed bind left the whole machine pointed at a port nobody was
    /// listening on — no internet, and nothing on screen saying why.
    func start(host: String, port: UInt16, rules: [Rule]) async throws {
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

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Resumed exactly once: the handler keeps firing over the listener's
            // life, and the first ready-or-failed is the answer to "did we bind".
            var settled = false
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if !settled { settled = true; continuation.resume() }
                case .failed(let error):
                    if settled {
                        // Died later: the supervisor puts the system proxy back
                        // rather than leaving traffic aimed at a dead port.
                        self.onFailure?(error.localizedDescription)
                    } else {
                        settled = true
                        listener.cancel()
                        continuation.resume(throwing: error)
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }

        self.listener = listener
        self.port = port
        Log.write(.info, "Yerel motor dinlemede: \(host):\(port)")
    }

    /// Cancels and waits for the port to come back.
    ///
    /// `cancel()` is as asynchronous as `start`, and restarting the engine —
    /// which a rule change or the relaunch button does — used to rebind the
    /// same port while the old listener was still holding it. That is where the
    /// "Address already in use" came from: not another program, us.
    func stopAndWait() async {
        guard let listener else { return stop() }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var settled = false
            listener.stateUpdateHandler = { state in
                if case .cancelled = state, !settled {
                    settled = true
                    continuation.resume()
                }
            }
            stop()
            // The handler is the normal path; this is the seatbelt for a
            // listener that was never ready and so never reports cancelled.
            queue.asyncAfter(deadline: .now() + 2) {
                if !settled { settled = true; continuation.resume() }
            }
        }
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

}
