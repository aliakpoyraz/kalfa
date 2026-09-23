import Foundation
import Network

enum EngineError: LocalizedError {
    case portBusy(Int)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .portBusy(let p):
            return "\(p) portu başkası tarafından kullanılıyor. Ayarlardan portu değiştir."
        case .launchFailed(let m):
            return "Motor başlatılamadı: \(m)"
        }
    }
}

/// The engine abstraction.
///
/// It was written when the engine was someone else's binary that Kalfa
/// supervised as a child process, and it is what made replacing that binary a
/// contained change: the rules, the watchers and the interface above it never
/// learned which one they were driving.
protocol Engine: AnyObject {
    var isRunning: Bool { get }
    /// Called when the engine stops on its own.
    var onUnexpectedExit: ((String) -> Void)? { get set }
    /// Returns once the engine is actually accepting connections, or throws.
    /// The caller turns the system proxy on right after, so "started" has to
    /// mean started.
    func start(config: AppConfig, host: String, port: Int) async throws
    func updateRules(config: AppConfig)
    /// Immediate teardown, for quitting.
    func stop()
    /// Teardown that waits for the port to be free, for restarts.
    func stopAndWait() async
}

/// Kalfa's own engine: an HTTP proxy in this process.
///
/// What it replaced: a bundled `spoofdpi` binary, the TOML file generated for
/// it on every start, a child process with its own crash handling, a hunt for
/// orphans left behind by the last crash, and an `lsof` call to find out
/// whether a port was free. All of that was plumbing around the fact that the
/// engine lived somewhere else.
///
/// What it gained: TLS record fragmentation, which byte splitting cannot do;
/// rule changes that take effect on the next connection instead of needing a
/// restart; and an Intel build for free.
final class NativeEngine: Engine {

    private let server = ProxyServer()
    var onUnexpectedExit: ((String) -> Void)?

    var isRunning: Bool { server.isRunning }

    func start(config: AppConfig, host: String, port: Int) async throws {
        guard !isRunning else { return }

        server.onFailure = { [weak self] message in
            Log.write(.error, "Yerel motor durdu: \(message)")
            DispatchQueue.main.async { self?.onUnexpectedExit?(message) }
        }

        do {
            try await server.start(host: host, port: UInt16(clamping: port),
                                   rules: Self.rules(from: config))
        } catch {
            // A busy port is the one failure worth naming: it is the only one
            // the person can do something about.
            if (error as? NWError) == .posix(.EADDRINUSE) { throw EngineError.portBusy(port) }
            throw EngineError.launchFailed(error.localizedDescription)
        }
    }

    /// A rule edit no longer means stopping and starting: the table is swapped
    /// where it is read.
    func updateRules(config: AppConfig) {
        server.setRules(Self.rules(from: config))
    }

    func stop() {
        server.stop()
    }

    func stopAndWait() async {
        await server.stopAndWait()
    }

    private static func rules(from config: AppConfig) -> [ProxyServer.Rule] {
        config.groups
            .filter { $0.enabled && !$0.domains.isEmpty }
            .map { group in
                ProxyServer.Rule(
                    domains: group.domains.map { $0.trimmingCharacters(in: .whitespaces).lowercased() },
                    mode: group.splitMode,
                    chunkSize: group.chunkSize,
                    dns: group.dnsMode,
                    name: group.name,
                    priority: group.priority
                )
            }
    }
}
