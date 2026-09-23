import Foundation

/// Turns one client write into several, so that a middlebox reading the stream
/// one packet at a time never sees the whole server name in a single read.
///
/// Every strategy here is legal and lossless: the bytes that arrive at the
/// server are byte-for-byte what the client sent — only the shape of the write
/// changes. That is the whole trick, and the reason it needs no privileges.
///
/// What is deliberately *not* here: fake packets with a short TTL, deliberately
/// reordered segments, and the rest of the desync family. Those need raw
/// sockets, which need root or a Network Extension. The embedded engine Kalfa
/// used before could not do them either, so nothing was lost by writing this.
enum Fragmenter {

    static func fragments(for data: Data, mode: SplitMode, chunkSize: Int) -> [Data] {
        guard data.count > 1 else { return [data] }

        switch mode {
        case .none:
            return [data]

        case .chunk:
            return splitting(data, at: [max(1, min(chunkSize, data.count - 1))])

        case .sni:
            // Split inside the hostname itself. The strongest of the TCP-level
            // tricks when it works, and the one most likely to be noticed: some
            // servers dislike a ClientHello arriving in two reads.
            guard let parsed = TLSClientHello.parse(data), let host = parsed.hostnameBytes else {
                return splitting(data, at: [max(1, min(chunkSize, data.count - 1))])
            }
            return splitting(data, at: [host.lowerBound + host.count / 2])

        case .random:
            // A few cuts at unpredictable places. Useful against a filter that
            // learned where the fixed ones are.
            let count = min(max(chunkSize, 2), 5)
            var points = Set<Int>()
            while points.count < count - 1 {
                points.insert(Int.random(in: 1..<data.count))
            }
            return splitting(data, at: points.sorted())

        case .record, .disorder, .fake:
            // Record-level fragmentation, and where the two strategies that need
            // raw sockets land. Their configs still decode — someone upgrading
            // keeps their rules — and they get the nearest thing that works in
            // user space rather than an error.
            return records(data, pieceSize: max(1, chunkSize))
        }
    }

    /// Cuts a buffer at the given absolute offsets.
    private static func splitting(_ data: Data, at points: [Int]) -> [Data] {
        var result: [Data] = []
        var start = data.startIndex
        for point in points {
            let index = data.index(data.startIndex, offsetBy: point)
            guard index > start, index < data.endIndex else { continue }
            result.append(data[start..<index])
            start = index
        }
        result.append(data[start..<data.endIndex])
        return result.filter { !$0.isEmpty }
    }

    /// Re-frames one TLS handshake record as several smaller records.
    ///
    /// A handshake message is allowed to span records — TLS says so, every
    /// server implements it — so this is not a trick the far end has to
    /// tolerate. It survives a filter that reassembles the TCP stream before
    /// looking, which plain byte splitting does not.
    private static func records(_ data: Data, pieceSize: Int) -> [Data] {
        guard let parsed = TLSClientHello.parse(data), parsed.payload.count > pieceSize else {
            return [data]
        }
        let bytes = [UInt8](data)
        let payload = Array(bytes[parsed.payload])
        // Small enough to split the server name across records, large enough
        // not to produce a hundred packets out of one hello.
        let size = max(pieceSize, 24)

        var result: [Data] = []
        var offset = 0
        while offset < payload.count {
            let end = min(offset + size, payload.count)
            let slice = payload[offset..<end]
            var record: [UInt8] = [0x16,
                                   UInt8(parsed.recordVersion >> 8),
                                   UInt8(parsed.recordVersion & 0xFF),
                                   UInt8(slice.count >> 8),
                                   UInt8(slice.count & 0xFF)]
            record.append(contentsOf: slice)
            result.append(Data(record))
            offset = end
        }

        // Anything the client piled on after this record travels as it was.
        if parsed.payload.upperBound < bytes.count {
            result.append(Data(bytes[parsed.payload.upperBound...]))
        }
        return result
    }
}
