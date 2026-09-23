import CoreGraphics
import Foundation
import IOKit

/// Hardware brightness and contrast over DDC/CI.
///
/// On Apple Silicon the only route to a monitor's I2C bus is `IOAVService`, taken
/// from the `DCPAVServiceProxy` node that the display controller publishes. The
/// public `IOFramebuffer` I2C interface used on Intel does not exist here.
///
/// Wire format is the DDC/CI standard, wrapped by IOAVService's own addressing:
/// every packet goes to chip `0x37` at sub-address `0x51`, and the checksum seed
/// is `0x6E ^ 0x51` (destination address XOR sub-address) rather than the plain
/// `0x6E` used on a raw bus.
///
/// All I2C work happens on one serial queue. Monitors drop concurrent DDC traffic,
/// and a slider that fires per-frame would otherwise flood the bus.
final class DDCService: @unchecked Sendable {

    static let shared = DDCService()

    /// VCP feature codes (DDC/CI spec, Table 8-1).
    enum VCP: UInt8 {
        case brightness = 0x10
        case contrast   = 0x12
    }

    struct Reading {
        let current: UInt16
        let max: UInt16

        /// 0-100 regardless of the monitor's internal range.
        var percent: Int {
            guard max > 0 else { return 0 }
            return Int((Double(current) / Double(max) * 100).rounded())
        }
    }

    private let queue = DispatchQueue(label: "com.aliakpoyraz.kalfa.ddc", qos: .userInitiated)

    private init() {}

    /// Whether this machine has a DDC path at all.
    var isSupported: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    // MARK: Public API

    /// Reads a VCP feature. Returns nil when the monitor does not answer.
    func read(_ feature: VCP, from displayID: CGDirectDisplayID) async -> Reading? {
        #if arch(arm64)
        if let cached = cache.value(for: displayID, feature: feature) { return cached }
        return await withCheckedContinuation { continuation in
            queue.async {
                let result = self.readSync(feature, displayID)
                if let result { self.cache.store(result, for: displayID, feature: feature) }
                continuation.resume(returning: result)
            }
        }
        #else
        return nil
        #endif
    }

    /// Writes a 0-100 percentage, scaled into the monitor's own range.
    @discardableResult
    func write(_ feature: VCP, percent: Int, to displayID: CGDirectDisplayID) async -> Bool {
        #if arch(arm64)
        let clamped = min(max(percent, 0), 100)
        let maxValue = await read(feature, from: displayID)?.max ?? 100
        let raw = UInt16((Double(clamped) / 100 * Double(maxValue)).rounded())

        return await withCheckedContinuation { continuation in
            queue.async {
                let ok = self.writeSync(feature, raw, displayID)
                if ok {
                    self.cache.store(
                        Reading(current: raw, max: maxValue), for: displayID, feature: feature
                    )
                }
                continuation.resume(returning: ok)
            }
        }
        #else
        return false
        #endif
    }

    /// Drops cached services and readings. Call after any display reconfiguration —
    /// the IORegistry nodes are rebuilt and old handles go stale.
    func invalidate() {
        cache.clear()
        #if arch(arm64)
        serviceLock.lock()
        serviceMap = nil
        serviceLock.unlock()
        #endif
    }

    // MARK: Reading cache

    /// A DDC round trip costs ~40 ms of mandated wait, so repeated reads while a
    /// menu is open must not hit the bus.
    private let cache = ReadingCache()

    private final class ReadingCache: @unchecked Sendable {
        private struct Key: Hashable {
            let displayID: CGDirectDisplayID
            let feature: UInt8
        }
        private struct Entry {
            let reading: Reading
            let time: Date
        }

        private let lock = NSLock()
        private var storage: [Key: Entry] = [:]
        private let ttl: TimeInterval = 5

        func value(for displayID: CGDirectDisplayID, feature: VCP) -> Reading? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = storage[Key(displayID: displayID, feature: feature.rawValue)],
                  Date().timeIntervalSince(entry.time) < ttl
            else { return nil }
            return entry.reading
        }

        func store(_ reading: Reading, for displayID: CGDirectDisplayID, feature: VCP) {
            lock.lock()
            storage[Key(displayID: displayID, feature: feature.rawValue)] =
                Entry(reading: reading, time: Date())
            lock.unlock()
        }

        func clear() {
            lock.lock()
            storage.removeAll()
            lock.unlock()
        }
    }

    #if arch(arm64)

    // MARK: Apple Silicon transport

    private static let chipAddress: UInt32 = 0x37
    private static let subAddress: UInt32 = 0x51
    /// DDC destination address XOR the sub-address IOAVService prepends for us.
    private static let checksumSeed: UInt8 = 0x6E ^ 0x51
    /// The spec's minimum wait between a Get request and its reply.
    private static let replyDelay: TimeInterval = 0.04

    private var serviceMap: [CGDirectDisplayID: IOAVServiceRef]?
    private let serviceLock = NSLock()

    private func writeSync(_ feature: VCP, _ value: UInt16, _ displayID: CGDirectDisplayID) -> Bool {
        guard let service = service(for: displayID) else { return false }

        // Set VCP Feature: length-flagged 0x84, opcode 0x03, code, value hi, value lo.
        var packet: [UInt8] = [
            0x84, 0x03, feature.rawValue,
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
        ]
        packet.append(Self.checksum(packet))

        let result = IOAVServiceWriteI2C(
            service, Self.chipAddress, Self.subAddress, &packet, UInt32(packet.count)
        )
        if result != kIOReturnSuccess {
            Log.ddc.error("write VCP 0x\(String(feature.rawValue, radix: 16), privacy: .public) failed: \(result)")
        }
        return result == kIOReturnSuccess
    }

    private func readSync(_ feature: VCP, _ displayID: CGDirectDisplayID) -> Reading? {
        guard let service = service(for: displayID) else { return nil }

        // Get VCP Feature request: 0x82, opcode 0x01, code.
        var request: [UInt8] = [0x82, 0x01, feature.rawValue]
        request.append(Self.checksum(request))

        guard IOAVServiceWriteI2C(
            service, Self.chipAddress, Self.subAddress, &request, UInt32(request.count)
        ) == kIOReturnSuccess else { return nil }

        Thread.sleep(forTimeInterval: Self.replyDelay)

        // Reply: [src, len, 0x02, result, code echo, type, max hi, max lo, cur hi, cur lo, checksum]
        var reply = [UInt8](repeating: 0, count: 12)
        guard IOAVServiceReadI2C(
            service, Self.chipAddress, Self.subAddress, &reply, UInt32(reply.count)
        ) == kIOReturnSuccess else { return nil }

        // Byte 3 is the result code; anything but zero means "unsupported feature".
        guard reply[2] == 0x02, reply[3] == 0x00, reply[4] == feature.rawValue else {
            Log.ddc.debug("VCP 0x\(String(feature.rawValue, radix: 16), privacy: .public) not supported by display")
            return nil
        }

        return Reading(
            current: UInt16(reply[8]) << 8 | UInt16(reply[9]),
            max: UInt16(reply[6]) << 8 | UInt16(reply[7])
        )
    }

    private static func checksum(_ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(checksumSeed, ^)
    }

    // MARK: Service discovery

    private func service(for displayID: CGDirectDisplayID) -> IOAVServiceRef? {
        serviceLock.lock()
        defer { serviceLock.unlock() }

        if serviceMap == nil { serviceMap = buildServiceMap() }
        return serviceMap?[displayID]
    }

    /// Pairs each external display with the I2C endpoint that drives it.
    ///
    /// Matching is by EDID vendor + product ID found by walking up from the
    /// `DCPAVServiceProxy` node, because the IORegistry order does not track the
    /// window server's display order. With a single external display the pairing
    /// is unambiguous and falls back to the lone candidate.
    private func buildServiceMap() -> [CGDirectDisplayID: IOAVServiceRef] {
        let externals = ScreenInfo.online().filter { $0.supportsDDC }
        guard !externals.isEmpty else { return [:] }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator
        ) == KERN_SUCCESS else {
            Log.ddc.error("no DCPAVServiceProxy nodes in IORegistry")
            return [:]
        }
        defer { IOObjectRelease(iterator) }

        var candidates: [(service: IOAVServiceRef, entry: io_service_t)] = []
        var entry = IOIteratorNext(iterator)
        while entry != IO_OBJECT_NULL {
            defer {
                let consumed = entry
                entry = IOIteratorNext(iterator)
                IOObjectRelease(consumed)
            }

            // Skip the internal panel's controller. Some drivers omit the key
            // entirely, so a missing value is treated as a candidate.
            if let location = property(entry, "Location") as? String, location != "External" {
                continue
            }
            guard let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry) else {
                continue
            }
            // Confirm the endpoint actually answers I2C before trusting it.
            var probe = [UInt8](repeating: 0, count: 32)
            guard IOAVServiceReadI2C(
                service, Self.chipAddress, Self.subAddress, &probe, 32
            ) == kIOReturnSuccess else { continue }

            IOObjectRetain(entry)
            candidates.append((service, entry))
        }

        defer { candidates.forEach { IOObjectRelease($0.entry) } }

        guard !candidates.isEmpty else {
            Log.ddc.error("no DCPAVServiceProxy answered I2C")
            return [:]
        }

        var map: [CGDirectDisplayID: IOAVServiceRef] = [:]
        var unmatched = candidates

        for screen in externals {
            guard let index = unmatched.firstIndex(where: { candidate in
                guard let identity = identity(of: candidate.entry) else { return false }
                return identity.vendor == screen.vendorID && identity.product == screen.modelID
            }) else { continue }
            map[screen.displayID] = unmatched[index].service
            unmatched.remove(at: index)
        }

        // Single unmatched display and single unmatched endpoint: the pairing is
        // forced, so take it. With more than one of either, guessing would mean
        // dimming the wrong monitor, so leave them unmapped.
        let remaining = externals.filter { map[$0.displayID] == nil }
        if remaining.count == 1, unmatched.count == 1 {
            map[remaining[0].displayID] = unmatched[0].service
        } else if !remaining.isEmpty {
            Log.ddc.warning("\(remaining.count) display(s) left unmatched to an I2C endpoint")
        }

        return map
    }

    /// Walks up to the nearest ancestor carrying EDID identity.
    private func identity(of entry: io_service_t) -> (vendor: UInt32, product: UInt32)? {
        var node = entry
        IOObjectRetain(node)
        defer { IOObjectRelease(node) }

        for _ in 0..<8 {
            if let vendor = property(node, "DisplayVendorID") as? NSNumber,
               let product = property(node, "DisplayProductID") as? NSNumber {
                return (vendor.uint32Value, product.uint32Value)
            }
            var parent: io_service_t = 0
            guard IORegistryEntryGetParentEntry(node, kIOServicePlane, &parent) == KERN_SUCCESS,
                  parent != 0
            else { return nil }
            IOObjectRelease(node)
            node = parent
        }
        return nil
    }

    private func property(_ entry: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }

    #endif
}
