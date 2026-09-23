import XCTest
@testable import EzDPIKit

/// The proxy is tested by using it: curl is pointed at the listener and has to
/// come back with a page. Byte-level tests prove the fragments are correct;
/// only this proves a real TLS handshake survives being cut in half.
///
/// Needs the network. Skips rather than fails when there is none — a red test
/// on a train is noise, not information.
final class ProxyServerTests: XCTestCase {

    private var server: ProxyServer!
    private var port: UInt16 = 0

    override func setUp() async throws {
        try XCTSkipUnless(Self.hasNetwork, "ağ yok, atlandı")

        port = UInt16.random(in: 29000...29900)
        server = ProxyServer()
        try await server.start(host: "127.0.0.1", port: port, rules: [
            ProxyServer.Rule(domains: ["example.com"], mode: .chunk, chunkSize: 2,
                             dns: .system, name: "test-chunk", priority: 100),
            ProxyServer.Rule(domains: ["httpbin.org"], mode: .record, chunkSize: 24,
                             dns: .system, name: "test-record", priority: 90),
        ])
    }

    override func tearDown() {
        server?.stop()
        server = nil
    }

    /// A matched host: the ClientHello goes out in two writes and the handshake
    /// still completes.
    func testMatchedHostOverChunkedHello() throws {
        let result = curl("https://example.com")
        XCTAssertEqual(result.code, "200", "eşleşen alan adı açılmadı: \(result.error)")
    }

    /// A matched host with record fragmentation — the strategy the bundled
    /// engine could not do.
    func testMatchedHostOverFragmentedRecords() throws {
        let result = curl("https://httpbin.org/status/200")
        XCTAssertEqual(result.code, "200", "kayıt parçalama başarısız: \(result.error)")
    }

    /// The reason the proxy can stay on permanently: a host no rule mentions is
    /// relayed untouched. This is the case that used to break payment pages.
    func testUnmatchedHostPassesThrough() throws {
        let result = curl("https://www.cloudflare.com")
        XCTAssertEqual(result.code, "200", "eşleşmeyen alan adı aktarılamadı: \(result.error)")
    }

    /// Plain HTTP arrives in absolute form and has to be rewritten to origin
    /// form before the server will answer it.
    func testPlainHTTP() throws {
        let result = curl("http://example.com")
        XCTAssertEqual(result.code, "200", "düz HTTP başarısız: \(result.error)")
    }

    /// A rule asking for DoH resolves the name somewhere other than the
    /// resolver that may be lying about it, then connects to the address it got
    /// back. If the lookup fails the session falls back to the system resolver,
    /// so this test is about the happy path actually being taken.
    func testResolvesOverHTTPS() async throws {
        let address = await DoHResolver.shared.resolve("example.com")
        let resolved = try XCTUnwrap(address, "DoH yanıt vermedi")
        XCTAssertTrue(resolved.contains("."), "A kaydı beklenirken \(resolved) geldi")

        // Second time from cache: same answer, no request.
        let cached = await DoHResolver.shared.resolve("example.com")
        XCTAssertEqual(cached, resolved)
    }

    /// `start` must not report success for a port it did not get.
    ///
    /// The version this replaces asked a "is the port busy?" helper that built
    /// an `NWListener` and never started it — and since a listener binds at
    /// `start()`, not at construction, the answer was always "free". The engine
    /// then reported success, the supervisor switched the system proxy on, and
    /// the bind failed a moment later: proxy on, engine dead, no internet.
    func testStartFailsOnATakenPort() async throws {
        let intruder = ProxyServer()
        do {
            try await intruder.start(host: "127.0.0.1", port: port, rules: [])
            intruder.stop()
            XCTFail("dolu porta bağlanma başarılı sayıldı")
        } catch {
            // Expected.
        }
    }

    /// And the port has to come back, or a restart cannot rebind it. This is
    /// what `stopAndWait` exists for: `cancel()` is as asynchronous as `start`.
    func testPortIsReusableAfterStopAndWait() async throws {
        await server.stopAndWait()
        server = nil

        let second = ProxyServer()
        try await second.start(host: "127.0.0.1", port: port, rules: [])
        second.stop()
    }

    // MARK: Helpers

    private func curl(_ url: String) -> (code: String, error: String) {
        let result = Shell.run("/usr/bin/curl", [
            "-s", "-o", "/dev/null", "-w", "%{http_code}",
            "--max-time", "25",
            "-x", "http://127.0.0.1:\(port)",
            url,
        ], timeout: 30)
        return (result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), result.stderr)
    }

    private static var hasNetwork: Bool {
        Shell.run("/usr/bin/curl", ["-s", "-o", "/dev/null", "--max-time", "8",
                                    "https://www.cloudflare.com"], timeout: 12).ok
    }
}
