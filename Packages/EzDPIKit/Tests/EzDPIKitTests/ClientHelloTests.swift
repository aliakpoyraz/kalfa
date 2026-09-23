import XCTest
@testable import EzDPIKit

/// A ClientHello built byte by byte, so the parser is checked against a known
/// layout rather than against whatever happened to be on the wire that day.
enum SampleHello {

    static func make(hostname: String) -> Data {
        let name = Array(hostname.utf8)

        // server_name extension body: list length, name type, name length, name
        var sniBody: [UInt8] = []
        sniBody += be16(name.count + 3)
        sniBody += [0x00]
        sniBody += be16(name.count)
        sniBody += name

        var extensions: [UInt8] = []
        extensions += be16(0x0000)              // server_name
        extensions += be16(sniBody.count)
        extensions += sniBody

        var body: [UInt8] = []
        body += be16(0x0303)                    // client_version
        body += [UInt8](repeating: 0xAB, count: 32)  // random
        body += [0x00]                          // session id length
        body += be16(2) + [0x13, 0x01]          // cipher suites
        body += [0x01, 0x00]                    // compression methods
        body += be16(extensions.count)
        body += extensions

        var handshake: [UInt8] = [0x01]         // client_hello
        handshake += be24(body.count)
        handshake += body

        var record: [UInt8] = [0x16]            // handshake record
        record += be16(0x0301)
        record += be16(handshake.count)
        record += handshake
        return Data(record)
    }

    static func be16(_ value: Int) -> [UInt8] { [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
    static func be24(_ value: Int) -> [UInt8] { [UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
}

final class ClientHelloTests: XCTestCase {

    func testFindsServerName() throws {
        let hello = SampleHello.make(hostname: "discord.com")
        let parsed = try XCTUnwrap(TLSClientHello.parse(hello))
        XCTAssertEqual(parsed.hostname, "discord.com")
        let range = try XCTUnwrap(parsed.hostnameBytes)
        XCTAssertEqual(String(decoding: hello[range], as: UTF8.self), "discord.com")
    }

    func testPayloadCoversTheWholeHandshake() throws {
        let hello = SampleHello.make(hostname: "example.org")
        let parsed = try XCTUnwrap(TLSClientHello.parse(hello))
        XCTAssertEqual(parsed.payload.lowerBound, 5)
        XCTAssertEqual(parsed.payload.upperBound, hello.count)
    }

    /// Anything that is not a handshake record is left alone. Guessing at bytes
    /// we cannot read is how a proxy breaks a payment page.
    func testIgnoresNonTLS() {
        XCTAssertNil(TLSClientHello.parse(Data("GET / HTTP/1.1\r\n\r\n".utf8)))
        XCTAssertNil(TLSClientHello.parse(Data([0x16, 0x03])))
        XCTAssertNil(TLSClientHello.parse(Data()))
    }

    /// A truncated hello must not crash the parser or read past the buffer.
    func testSurvivesTruncation() {
        let hello = SampleHello.make(hostname: "discord.com")
        for length in 5..<hello.count {
            _ = TLSClientHello.parse(hello.prefix(length))
        }
    }
}
