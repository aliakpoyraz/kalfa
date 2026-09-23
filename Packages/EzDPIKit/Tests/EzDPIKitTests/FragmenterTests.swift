import XCTest
@testable import EzDPIKit

/// The one property every strategy must hold: the server receives exactly the
/// bytes the client sent. Only the shape of the writes changes — if a strategy
/// ever loses or reorders a byte, TLS fails and the user blames the network.
final class FragmenterTests: XCTestCase {

    private let hello = SampleHello.make(hostname: "discord.com")

    func testByteSplittingIsLossless() {
        for mode in [SplitMode.chunk, .sni, .random, .none] {
            let pieces = Fragmenter.fragments(for: hello, mode: mode, chunkSize: 2)
            XCTAssertEqual(pieces.reduce(Data(), +), hello, "\(mode) baytları değiştirdi")
            XCTAssertFalse(pieces.contains { $0.isEmpty }, "\(mode) boş parça üretti")
        }
    }

    func testChunkCutsWhereAsked() {
        let pieces = Fragmenter.fragments(for: hello, mode: .chunk, chunkSize: 2)
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces[0].count, 2)
    }

    /// The point of the SNI strategy: the hostname cannot be read from either
    /// piece on its own.
    func testSNISplitCutsTheHostname() {
        let pieces = Fragmenter.fragments(for: hello, mode: .sni, chunkSize: 2)
        XCTAssertEqual(pieces.count, 2)
        for piece in pieces {
            XCTAssertFalse(String(decoding: piece, as: UTF8.self).contains("discord.com"))
        }
    }

    /// Record fragmentation rewrites the framing, so the test is not "same
    /// bytes" but "same handshake, in more records".
    func testRecordFragmentationKeepsTheHandshake() throws {
        let pieces = Fragmenter.fragments(for: hello, mode: .record, chunkSize: 24)
        XCTAssertGreaterThan(pieces.count, 1)

        var rebuilt = Data()
        for piece in pieces {
            let bytes = [UInt8](piece)
            XCTAssertEqual(bytes[0], 0x16, "her parça bir TLS kaydı olmalı")
            let declared = Int(bytes[3]) << 8 | Int(bytes[4])
            XCTAssertEqual(declared, bytes.count - 5, "kayıt uzunluğu gövdeyle uyuşmuyor")
            rebuilt.append(piece.dropFirst(5))
        }
        let original = try XCTUnwrap(TLSClientHello.parse(hello))
        XCTAssertEqual(rebuilt, hello[original.payload])
    }

    /// Configs written for the bundled engine still exist on disk. They must
    /// keep working rather than erroring, so the two raw-socket strategies run
    /// as the closest thing user space can do.
    func testLegacyModesFallBackToRecords() {
        for mode in [SplitMode.disorder, .fake] {
            let pieces = Fragmenter.fragments(for: hello, mode: mode, chunkSize: 24)
            XCTAssertGreaterThan(pieces.count, 1, "\(mode) parçalanmadı")
            XCTAssertEqual([UInt8](pieces[0])[0], 0x16)
        }
    }

    func testSingleByteIsLeftAlone() {
        let one = Data([0x16])
        XCTAssertEqual(Fragmenter.fragments(for: one, mode: .chunk, chunkSize: 2), [one])
    }
}
