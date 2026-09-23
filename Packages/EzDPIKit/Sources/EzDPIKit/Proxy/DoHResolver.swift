import Foundation

/// Name resolution over HTTPS, for rules that ask for it.
///
/// The point is not privacy in general — it is that the answer for a blocked
/// name comes from somewhere other than the resolver that is lying about it.
/// The server is addressed by IP literal, so resolving the resolver is not a
/// problem that needs solving.
final class DoHResolver: @unchecked Sendable {

    static let shared = DoHResolver()

    /// Cloudflare and Google, by address. Both present certificates that cover
    /// their own IPs, so the TLS check still means something.
    private let endpoints = [
        URL(string: "https://1.1.1.1/dns-query")!,
        URL(string: "https://8.8.8.8/dns-query")!,
    ]

    private struct Entry {
        let addresses: [String]
        let expires: Date
    }

    private let lock = NSLock()
    private var cache: [String: Entry] = [:]

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        // Never through ourselves: the proxy asking its own listener to resolve
        // a name is a deadlock waiting for the first slow lookup.
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration)
    }()

    /// Returns nil when every endpoint fails, and the caller falls back to the
    /// system resolver — a name that will not resolve is worse than a name
    /// resolved by the ISP.
    func resolve(_ host: String) async -> String? {
        if let hit = cached(host) { return hit }

        for endpoint in endpoints {
            guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { continue }
            components.queryItems = [
                URLQueryItem(name: "name", value: host),
                URLQueryItem(name: "type", value: "A"),
            ]
            guard let url = components.url else { continue }
            var request = URLRequest(url: url)
            request.setValue("application/dns-json", forHTTPHeaderField: "Accept")

            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let payload = try? JSONDecoder().decode(Answer.self, from: data)
            else { continue }

            let addresses = payload.Answer?.filter { $0.type == 1 }.map(\.data) ?? []
            guard let first = addresses.first else { continue }

            let ttl = payload.Answer?.first?.TTL ?? 300
            store(host: host, addresses: addresses, ttl: TimeInterval(min(max(ttl, 30), 3600)))
            return first
        }
        return nil
    }

    private func cached(_ host: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = cache[host], entry.expires > Date() else { return nil }
        return entry.addresses.first
    }

    private func store(host: String, addresses: [String], ttl: TimeInterval) {
        lock.lock()
        cache[host] = Entry(addresses: addresses, expires: Date().addingTimeInterval(ttl))
        lock.unlock()
    }

    private struct Answer: Decodable {
        struct Record: Decodable {
            let type: Int
            let data: String
            let TTL: Int?
        }
        let Answer: [Record]?
    }
}
