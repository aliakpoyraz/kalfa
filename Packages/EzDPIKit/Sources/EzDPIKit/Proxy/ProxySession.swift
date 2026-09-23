import Foundation
import Network

/// One browser connection, from the request line to the last relayed byte.
///
/// The shape is an ordinary HTTP proxy: read the request, open the other side,
/// then copy bytes in both directions until someone hangs up. The only unusual
/// step is that the first write towards a matched host is cut into pieces.
final class ProxySession {

    /// What a rule decided about this host.
    struct Decision {
        let mode: SplitMode
        let chunkSize: Int
        let dns: DNSMode
        let ruleName: String?

        /// Nothing matched: relay untouched. This is what lets the proxy stay on
        /// permanently — traffic Kalfa has no opinion about is not Kalfa's
        /// business, and a payment page never notices it is there.
        static let passthrough = Decision(mode: .none, chunkSize: 0, dns: .system, ruleName: nil)
    }

    private let client: NWConnection
    private let queue: DispatchQueue
    private let decide: @Sendable (String) -> Decision
    private var upstream: NWConnection?
    private var closed = false

    /// Told to the server so it can forget this session; without it the table
    /// of live connections only ever grows.
    var onFinish: (() -> Void)?

    init(client: NWConnection, queue: DispatchQueue, decide: @escaping @Sendable (String) -> Decision) {
        self.client = client
        self.queue = queue
        self.decide = decide
    }

    func start() {
        client.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.close() }
            if case .cancelled = state { self?.close() }
        }
        client.start(queue: queue)
        readRequest(buffer: Data())
    }

    // MARK: Request

    /// Reads until the blank line that ends the headers. Capped, because a
    /// client that never sends one is either broken or not speaking HTTP.
    private func readRequest(buffer: Data) {
        client.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard error == nil, let data, !data.isEmpty else {
                if isComplete || error != nil { self.close() }
                return
            }

            var accumulated = buffer
            accumulated.append(data)

            guard let headerEnd = accumulated.range(of: Data("\r\n\r\n".utf8)) else {
                if accumulated.count > 64 * 1024 { self.close() } else { self.readRequest(buffer: accumulated) }
                return
            }

            let head = String(decoding: accumulated[..<headerEnd.lowerBound], as: UTF8.self)
            let rest = accumulated[headerEnd.upperBound...]
            self.handle(head: head, remainder: Data(rest))
        }
    }

    private func handle(head: String, remainder: Data) {
        let lines = head.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let requestLine = lines.first else { return close() }
        let parts = requestLine.split(separator: " ").map(String.init)
        guard parts.count >= 3 else { return close() }

        if parts[0].uppercased() == "CONNECT" {
            let target = hostAndPort(parts[1], defaultPort: 443)
            connectTunnel(host: target.host, port: target.port)
        } else {
            // Plain HTTP through a proxy arrives in absolute form
            // (`GET http://host/path`); origin servers want the path alone.
            guard let url = URL(string: parts[1]), let host = url.host else { return close() }
            let port = UInt16(url.port ?? 80)
            var path = url.path.isEmpty ? "/" : url.path
            if let query = url.query { path += "?\(query)" }

            var rebuilt = "\(parts[0]) \(path) \(parts[2])\r\n"
            for line in lines.dropFirst() where !line.isEmpty {
                // Hop-by-hop: it describes the browser's link to us, not ours
                // to the server.
                if line.lowercased().hasPrefix("proxy-connection:") { continue }
                rebuilt += line + "\r\n"
            }
            rebuilt += "\r\n"

            var payload = Data(rebuilt.utf8)
            payload.append(remainder)
            openUpstream(host: host, port: port, firstWrite: payload, replyToClient: nil)
        }
    }

    private func connectTunnel(host: String, port: UInt16) {
        openUpstream(host: host, port: port, firstWrite: nil,
                     replyToClient: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8))
    }

    private func hostAndPort(_ authority: String, defaultPort: UInt16) -> (host: String, port: UInt16) {
        // IPv6 literals arrive bracketed: [::1]:443
        if authority.hasPrefix("["), let end = authority.firstIndex(of: "]") {
            let host = String(authority[authority.index(after: authority.startIndex)..<end])
            let tail = authority[authority.index(after: end)...]
            let port = UInt16(tail.dropFirst().description) ?? defaultPort
            return (host, port)
        }
        let pieces = authority.split(separator: ":")
        guard pieces.count == 2, let port = UInt16(pieces[1]) else { return (authority, defaultPort) }
        return (String(pieces[0]), port)
    }

    // MARK: Upstream

    private func openUpstream(host: String, port: UInt16, firstWrite: Data?, replyToClient: Data?) {
        let decision = decide(host.lowercased())

        Task { [weak self] in
            guard let self else { return }
            var endpointHost = host
            if decision.dns == .https, !host.isIPAddress, let resolved = await DoHResolver.shared.resolve(host) {
                endpointHost = resolved
            }

            let options = NWProtocolTCP.Options()
            // Without this the kernel is free to coalesce the pieces back into
            // one segment, and the whole exercise achieves nothing.
            options.noDelay = true
            options.connectionTimeout = 10

            let connection = NWConnection(
                host: NWEndpoint.Host(endpointHost),
                port: NWEndpoint.Port(rawValue: port) ?? 443,
                using: NWParameters(tls: nil, tcp: options)
            )
            self.upstream = connection

            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if let replyToClient {
                        self.send(replyToClient, over: self.client) {
                            self.pumpFirstClientWrite(decision: decision)
                        }
                    }
                    if let firstWrite {
                        self.sendFragmented(firstWrite, decision: decision, over: connection) {
                            self.relay(from: connection, to: self.client)
                            self.relay(from: self.client, to: connection)
                        }
                    } else if replyToClient == nil {
                        self.relay(from: connection, to: self.client)
                        self.relay(from: self.client, to: connection)
                    }
                    if let name = decision.ruleName {
                        Log.write(.info, "\(host) · \(name)")
                    }
                case .failed(let error):
                    Log.write(.warn, "\(host) bağlanamadı: \(error.localizedDescription)")
                    self.close()
                case .cancelled:
                    self.close()
                default:
                    break
                }
            }
            connection.start(queue: self.queue)
        }
    }

    /// The tunnel's first client write is the TLS ClientHello — the one packet
    /// worth reshaping. Everything after it is ciphertext and travels as is.
    private func pumpFirstClientWrite(decision: Decision) {
        client.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, let upstream = self.upstream else { return }
            guard error == nil, let data, !data.isEmpty else {
                if isComplete || error != nil { self.close() }
                return
            }
            self.sendFragmented(data, decision: decision, over: upstream) {
                self.relay(from: upstream, to: self.client)
                self.relay(from: self.client, to: upstream)
            }
        }
    }

    private func sendFragmented(_ data: Data, decision: Decision, over connection: NWConnection, then: @escaping () -> Void) {
        let pieces = Fragmenter.fragments(for: data, mode: decision.mode, chunkSize: decision.chunkSize)
        guard pieces.count > 1 else { return send(data, over: connection, then: then) }

        // One at a time, each waiting for the last to be handed to the kernel:
        // queuing them together would let them be written as a single segment.
        func write(_ index: Int) {
            guard index < pieces.count else { return then() }
            send(pieces[index], over: connection) { write(index + 1) }
        }
        write(0)
    }

    private func send(_ data: Data, over connection: NWConnection, then: @escaping () -> Void) {
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil { self?.close() } else { then() }
        })
    }

    // MARK: Relay

    private func relay(from source: NWConnection, to destination: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                destination.send(content: data, completion: .contentProcessed { error in
                    if error != nil { self.close() } else { self.relay(from: source, to: destination) }
                })
            } else if isComplete || error != nil {
                self.close()
            } else {
                self.relay(from: source, to: destination)
            }
        }
    }

    // MARK: Teardown

    /// Torn down from outside, when the engine stops with tunnels still open.
    func cancel() { close() }

    /// Idempotent on purpose: both directions of the relay and both state
    /// handlers can arrive at "this is over" at the same moment.
    private func close() {
        guard !closed else { return }
        closed = true
        client.cancel()
        upstream?.cancel()
        upstream = nil
        onFinish?()
        onFinish = nil
    }
}

private extension String {
    /// Good enough to decide "do not ask a resolver about this".
    var isIPAddress: Bool {
        var v4 = in_addr()
        if inet_pton(AF_INET, self, &v4) == 1 { return true }
        var v6 = in6_addr()
        return inet_pton(AF_INET6, self, &v6) == 1
    }
}
