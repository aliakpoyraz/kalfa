import Foundation

/// Just enough TLS to find the interesting bytes in a ClientHello.
///
/// Kalfa never decrypts anything and never becomes a certificate authority —
/// it only needs to know where the record header ends and where the server name
/// sits, so the same bytes can be handed to the network in a different shape.
enum TLSClientHello {

    struct Parsed {
        /// The five-byte record header: type, version, length.
        let recordVersion: UInt16
        /// Everything after the record header, i.e. the handshake message.
        let payload: Range<Int>
        /// Where the SNI hostname's characters sit in the original buffer.
        let hostnameBytes: Range<Int>?
        let hostname: String?
    }

    /// Returns nil for anything that is not a TLS handshake record — plain
    /// HTTP, a continuation of an earlier record, or a protocol we do not know.
    /// Callers treat nil as "pass it through untouched", which is the right
    /// default: mangling bytes we cannot read is how a proxy breaks payment
    /// pages.
    static func parse(_ data: Data) -> Parsed? {
        let bytes = [UInt8](data)
        guard bytes.count >= 5, bytes[0] == 0x16 else { return nil }

        let recordVersion = UInt16(bytes[1]) << 8 | UInt16(bytes[2])
        let recordLength = Int(bytes[3]) << 8 | Int(bytes[4])
        let payloadEnd = min(5 + recordLength, bytes.count)
        guard payloadEnd > 5 else { return nil }

        // Handshake: type(1) length(3), then the ClientHello body.
        var cursor = 5
        guard bytes.count > cursor, bytes[cursor] == 0x01 else {
            return Parsed(recordVersion: recordVersion,
                          payload: 5..<payloadEnd,
                          hostnameBytes: nil,
                          hostname: nil)
        }
        cursor += 4                                   // handshake header
        cursor += 2                                   // client_version
        cursor += 32                                  // random

        guard let afterSession = skipVector(bytes, at: cursor, lengthBytes: 1) else {
            return Parsed(recordVersion: recordVersion, payload: 5..<payloadEnd,
                          hostnameBytes: nil, hostname: nil)
        }
        guard let afterCiphers = skipVector(bytes, at: afterSession, lengthBytes: 2),
              let afterCompression = skipVector(bytes, at: afterCiphers, lengthBytes: 1)
        else {
            return Parsed(recordVersion: recordVersion, payload: 5..<payloadEnd,
                          hostnameBytes: nil, hostname: nil)
        }

        var extensionsCursor = afterCompression
        guard extensionsCursor + 2 <= bytes.count else {
            return Parsed(recordVersion: recordVersion, payload: 5..<payloadEnd,
                          hostnameBytes: nil, hostname: nil)
        }
        let extensionsLength = Int(bytes[extensionsCursor]) << 8 | Int(bytes[extensionsCursor + 1])
        extensionsCursor += 2
        let extensionsEnd = min(extensionsCursor + extensionsLength, bytes.count)

        while extensionsCursor + 4 <= extensionsEnd {
            let type = Int(bytes[extensionsCursor]) << 8 | Int(bytes[extensionsCursor + 1])
            let length = Int(bytes[extensionsCursor + 2]) << 8 | Int(bytes[extensionsCursor + 3])
            let body = extensionsCursor + 4
            guard body + length <= bytes.count else { break }

            // server_name (0) -> list_length(2) name_type(1) name_length(2) name
            if type == 0, length >= 5 {
                let nameLength = Int(bytes[body + 3]) << 8 | Int(bytes[body + 4])
                let nameStart = body + 5
                if nameStart + nameLength <= bytes.count, nameLength > 0 {
                    let range = nameStart..<(nameStart + nameLength)
                    let host = String(bytes: bytes[range], encoding: .utf8)
                    return Parsed(recordVersion: recordVersion,
                                  payload: 5..<payloadEnd,
                                  hostnameBytes: range,
                                  hostname: host)
                }
            }
            extensionsCursor = body + length
        }

        return Parsed(recordVersion: recordVersion, payload: 5..<payloadEnd,
                      hostnameBytes: nil, hostname: nil)
    }

    /// Steps over a length-prefixed vector, returning the index after it.
    private static func skipVector(_ bytes: [UInt8], at index: Int, lengthBytes: Int) -> Int? {
        guard index + lengthBytes <= bytes.count else { return nil }
        var length = 0
        for offset in 0..<lengthBytes {
            length = length << 8 | Int(bytes[index + offset])
        }
        let next = index + lengthBytes + length
        return next <= bytes.count ? next : nil
    }
}
