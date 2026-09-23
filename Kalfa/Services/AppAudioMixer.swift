import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import Observation

/// Per-application sound: a level, a mute, a meter, and which speakers each app
/// plays through.
///
/// macOS has no such control of its own. The mechanism is a process tap per app
/// (macOS 14.2+) feeding a private aggregate device: a tap that mutes its source
/// hands us the samples to render ourselves, which is what makes both a level
/// and a different output device possible. A tap that does not mute is used for
/// metering alone, so watching the bars never changes what is heard.
@available(macOS 14.2, *)
@MainActor
@Observable
final class AppAudioMixer {
    static let shared = AppAudioMixer()

    struct Process: Identifiable {
        let id: String
        let audioObjectIDs: [AudioObjectID]
        let name: String
        let icon: NSImage
    }

    enum TapPermission {
        case granted
        case denied(OSStatus)
        /// Nothing was playing, so there was nothing to ask permission about.
        case unknown
    }

    private(set) var processes: [Process] = []
    private(set) var statusMessage: String?
    /// 0...1 peak per process id, decayed for the eye rather than the meter.
    private(set) var meters: [String: Double] = [:]

    private var router: AppAudioRouter?
    private var refreshTimer: Timer?
    private var meterTimer: Timer?
    private var isMonitoring = false
    private let defaults = UserDefaults.standard
    private static let levelsKey = "appAudioMixerLevels"
    private static let devicesKey = "appAudioMixerDevices"

    private init() {}

    // MARK: Lifecycle

    /// Called while the mixer is on screen. Monitoring taps every app that is
    /// playing so the meters have something to show; it is switched off again the
    /// moment the panel closes, leaving only the apps that were actually adjusted.
    func setMonitoring(_ monitoring: Bool) {
        guard isMonitoring != monitoring else { return }
        isMonitoring = monitoring
        if monitoring {
            start()
            meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.readMeters() }
            }
        } else {
            meterTimer?.invalidate()
            meterTimer = nil
            meters = [:]
        }
        rebuildRouter()
    }

    func start() {
        refresh()
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let discovered = Self.audioProcesses()
        let oldSignature = processes.map { "\($0.id):\($0.audioObjectIDs)" }
        let newSignature = discovered.map { "\($0.id):\($0.audioObjectIDs)" }
        processes = discovered
        guard oldSignature != newSignature else { return }
        if isMonitoring || !activeRouteIDs().isEmpty { rebuildRouter() }
    }

    // MARK: Level, mute, meter

    func level(for process: Process) -> Double {
        storedLevels()[process.id] ?? 1
    }

    func setLevel(_ value: Double, for process: Process) {
        let level = min(max(value, 0), 1)
        var levels = storedLevels()
        levels[process.id] = level
        defaults.set(levels, forKey: Self.levelsKey)

        // A level change inside an existing route set is a write to one float;
        // anything that changes which taps exist has to be rebuilt.
        if router?.routeIDs == routeIDs() {
            router?.setLevel(Float(level), for: process.id)
            if router?.isSilenced(process.id) != (level < 0.995) { rebuildRouter() }
        } else {
            rebuildRouter()
        }
    }

    func toggleMute(for process: Process) {
        setLevel(level(for: process) > 0 ? 0 : 1, for: process)
    }

    func meter(for process: Process) -> Double {
        meters[process.id] ?? 0
    }

    // MARK: Output device per app

    /// `nil` means "wherever the system is playing".
    func deviceUID(for process: Process) -> String? {
        storedDevices()[process.id]
    }

    func deviceName(for process: Process) -> String? {
        guard let uid = deviceUID(for: process) else { return nil }
        return AudioService.shared.outputs.first { $0.uid == uid }?.name
    }

    func setDevice(_ uid: String?, for process: Process) {
        var devices = storedDevices()
        devices[process.id] = uid
        defaults.set(devices, forKey: Self.devicesKey)
        rebuildRouter()
    }

    func resetAll() {
        router?.stop()
        router = nil
        defaults.removeObject(forKey: Self.levelsKey)
        defaults.removeObject(forKey: Self.devicesKey)
        statusMessage = nil
        meters = [:]
        if isMonitoring { rebuildRouter() }
    }

    // MARK: Routing

    /// Which processes need a tap at all.
    private func routeIDs() -> Set<String> {
        isMonitoring
            ? Set(processes.map(\.id))
            : activeRouteIDs()
    }

    /// Processes whose sound Kalfa is actually changing.
    private func activeRouteIDs() -> Set<String> {
        Set(
            processes
                .filter { level(for: $0) < 0.995 || deviceUID(for: $0) != nil }
                .map(\.id)
        )
    }

    private func rebuildRouter() {
        let wanted = routeIDs()
        let defaultUID = try? AppAudioRouter.defaultOutput().uid

        let specs = processes.compactMap { process -> AppAudioRouter.Route? in
            guard wanted.contains(process.id) else { return nil }
            let level = level(for: process)
            let target = deviceUID(for: process)
            // Silenced means the tap takes the audio away from the system and
            // Kalfa renders it: needed for a level below full, or for sending the
            // app somewhere other than where everything else is going.
            let isSilenced = level < 0.995 || (target != nil && target != defaultUID)
            guard let deviceUID = target ?? defaultUID else { return nil }
            return .init(
                id: process.id,
                processIDs: process.audioObjectIDs,
                name: process.name,
                level: Float(level),
                deviceUID: deviceUID,
                isSilenced: isSilenced
            )
        }

        guard !specs.isEmpty else {
            router?.stop()
            router = nil
            statusMessage = nil
            return
        }

        do {
            let replacement = try AppAudioRouter(routes: specs)
            router?.stop()
            router = replacement
            statusMessage = nil
        } catch {
            statusMessage = L10n.t("mixer.error.detail", String(describing: error))
        }
    }

    private func readMeters() {
        guard let router else {
            if !meters.isEmpty { meters = [:] }
            return
        }
        let peaks = router.drainPeaks()
        var updated: [String: Double] = [:]
        for process in processes {
            let peak = Double(peaks[process.id] ?? 0)
            // Fall rather than jump: a meter that tracks every buffer reads as
            // flicker at 20 frames a second.
            let previous = meters[process.id] ?? 0
            updated[process.id] = max(peak, previous * 0.72)
        }
        meters = updated
    }

    // MARK: Permission

    /// Creates and immediately destroys a metering tap to see whether macOS lets
    /// Kalfa listen at all. The answer is cached once it is yes: the permission
    /// is not taken back while the app runs, and probing on a timer would create
    /// a tap every few seconds for nothing.
    private static var cachedPermission: TapPermission?

    static func probeTapPermission() -> TapPermission {
        if case .granted = cachedPermission { return .granted }

        let candidates = readAudioObjectIDs(
            object: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyProcessObjectList
        ).filter { readUInt32(object: $0, selector: kAudioProcessPropertyIsRunningOutput) != 0 }

        guard let candidate = candidates.first else { return .unknown }

        let description = CATapDescription(stereoMixdownOfProcesses: [candidate])
        description.name = "Kalfa · probe"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else {
            cachedPermission = .denied(status)
            return .denied(status)
        }
        AudioHardwareDestroyProcessTap(tap)
        cachedPermission = .granted
        return .granted
    }

    // MARK: Stored values

    private func storedLevels() -> [String: Double] {
        defaults.dictionary(forKey: Self.levelsKey) as? [String: Double] ?? [:]
    }

    private func storedDevices() -> [String: String] {
        defaults.dictionary(forKey: Self.devicesKey) as? [String: String] ?? [:]
    }

    // MARK: Process discovery

    private struct RawProcess {
        let objectID: AudioObjectID
        let ownerID: String
        let name: String
        let icon: NSImage
    }

    private static func audioProcesses() -> [Process] {
        let objectIDs = readAudioObjectIDs(
            object: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyProcessObjectList
        )

        let raw: [RawProcess] = objectIDs.compactMap { objectID in
            guard readUInt32(object: objectID, selector: kAudioProcessPropertyIsRunningOutput) != 0,
                  let pid = readPID(object: objectID), pid != getpid()
            else { return nil }

            guard let owner = ownerInfo(
                for: NSRunningApplication(processIdentifier: pid),
                pid: pid,
                fallbackBundleID: readString(object: objectID, selector: kAudioProcessPropertyBundleID)
            ) else { return nil }
            return RawProcess(objectID: objectID, ownerID: owner.id, name: owner.name, icon: owner.icon)
        }

        return Dictionary(grouping: raw, by: \.ownerID).compactMap { ownerID, entries in
            guard let first = entries.first else { return nil }
            return Process(
                id: ownerID,
                audioObjectIDs: entries.map(\.objectID).sorted(),
                name: first.name,
                icon: first.icon
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func ownerInfo(
        for app: NSRunningApplication?,
        pid: pid_t,
        fallbackBundleID: String?
    ) -> (id: String, name: String, icon: NSImage)? {
        let resolvedApp = appWithBundle(for: app, audioBundleID: fallbackBundleID)
        // Helper processes (Arc and every other Chromium browser play through one)
        // are often not registered with LaunchServices, so the executable's path is
        // what leads back to the application the person recognises.
        let bundleURL = resolvedApp?.bundleURL ?? executableURL(forPID: pid)
        if let bundleURL,
           let ownerURL = outermostApplicationURL(in: bundleURL),
           let bundle = Bundle(url: ownerURL) {
            let id = bundle.bundleIdentifier ?? fallbackBundleID ?? ownerURL.path
            let name = (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.localizedInfoDictionary?["CFBundleName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                ?? ownerURL.deletingPathExtension().lastPathComponent
            return (id, name, NSWorkspace.shared.icon(forFile: ownerURL.path))
        }

        guard let fallbackBundleID else { return nil }
        let icon = resolvedApp?.icon ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage()
        return (fallbackBundleID, resolvedApp?.localizedName ?? fallbackBundleID, icon)
    }

    private static func executableURL(forPID pid: pid_t) -> URL? {
        var buffer = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }

    private static func appWithBundle(
        for processApp: NSRunningApplication?,
        audioBundleID: String?
    ) -> NSRunningApplication? {
        if processApp?.bundleURL != nil { return processApp }
        guard let audioBundleID else { return processApp }
        let audioID = audioBundleID.lowercased()
        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard let bundleID = app.bundleIdentifier?.lowercased(), app.bundleURL != nil else { return false }
                return audioID == bundleID || audioID.hasPrefix(bundleID + ".")
            }
            .max { ($0.bundleIdentifier?.count ?? 0) < ($1.bundleIdentifier?.count ?? 0) }
            ?? processApp
    }

    private static func outermostApplicationURL(in url: URL) -> URL? {
        let components = url.standardizedFileURL.pathComponents
        guard let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: Array(components.prefix(appIndex + 1))))
    }

    // MARK: CoreAudio reads

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    fileprivate static func readAudioObjectIDs(object: AudioObjectID, selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var property = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size) == noErr else { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = values.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0.baseAddress!)
        }
        return status == noErr ? values : []
    }

    fileprivate static func readUInt32(object: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32 {
        var property = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value)
        return value
    }

    private static func readPID(object: AudioObjectID) -> pid_t? {
        var property = address(kAudioProcessPropertyPID)
        var value = pid_t(0)
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func readString(object: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var property = address(selector)
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0)
        }
        return status == noErr ? value as String? : nil
    }
}

// MARK: - The audio engine

/// Owns one private aggregate device per destination, and the taps feeding it.
@available(macOS 14.2, *)
private final class AppAudioRouter {

    struct Route {
        let id: String
        let processIDs: [AudioObjectID]
        let name: String
        let level: Float
        /// Where this app should come out.
        let deviceUID: String
        /// Whether the tap takes the audio away from the system (Kalfa renders it)
        /// or merely listens (metering only).
        let isSilenced: Bool
    }

    let routeIDs: Set<String>

    private let orderedIDs: [String]
    private let silenced: Set<String>
    /// Shared with the audio threads: gains are written by the UI, peaks written
    /// by the audio threads and drained by the UI. Both are plain floats, one
    /// slot per route, so neither side can tear the other's value.
    private let gains: UnsafeMutablePointer<Float>
    private let peaks: UnsafeMutablePointer<Float>
    private let slotCount: Int
    private var engines: [Engine] = []

    init(routes: [Route]) throws {
        routeIDs = Set(routes.map(\.id))
        orderedIDs = routes.map(\.id)
        silenced = Set(routes.filter(\.isSilenced).map(\.id))
        slotCount = routes.count
        gains = .allocate(capacity: routes.count)
        gains.initialize(from: routes.map(\.level), count: routes.count)
        peaks = .allocate(capacity: routes.count)
        peaks.initialize(repeating: 0, count: routes.count)

        do {
            // One aggregate per destination device: an aggregate renders to a
            // single main sub-device, so sending two apps to two different pairs
            // of speakers means two of them.
            for (deviceUID, indices) in Dictionary(grouping: routes.indices, by: { routes[$0].deviceUID }) {
                let engine = try Engine(
                    deviceUID: deviceUID,
                    routes: indices.map { (index: $0, route: routes[$0]) },
                    gains: gains,
                    peaks: peaks
                )
                engines.append(engine)
            }
        } catch {
            stop()
            gains.deinitialize(count: slotCount)
            gains.deallocate()
            peaks.deinitialize(count: slotCount)
            peaks.deallocate()
            throw error
        }
    }

    deinit {
        stop()
        gains.deinitialize(count: slotCount)
        gains.deallocate()
        peaks.deinitialize(count: slotCount)
        peaks.deallocate()
    }

    func setLevel(_ level: Float, for id: String) {
        guard let index = orderedIDs.firstIndex(of: id) else { return }
        gains[index] = level
    }

    func isSilenced(_ id: String) -> Bool {
        silenced.contains(id)
    }

    /// Reads and clears the peak each route reached since the last look.
    func drainPeaks() -> [String: Float] {
        var result: [String: Float] = [:]
        for (index, id) in orderedIDs.enumerated() {
            result[id] = peaks[index]
            peaks[index] = 0
        }
        return result
    }

    func stop() {
        for engine in engines { engine.stop() }
        engines.removeAll()
    }

    // MARK: One destination

    private final class Engine {
        private var taps: [AudioObjectID] = []
        private var aggregateID = AudioObjectID(kAudioObjectUnknown)
        private var ioProcID: AudioDeviceIOProcID?
        private let queue = DispatchQueue(label: "com.aliakpoyraz.kalfa.audio-mixer", qos: .userInteractive)
        /// Per-tap route slot and "is ours to render", in tap-list order. Raw
        /// buffers rather than arrays because the IO block runs on a real-time
        /// thread, where Swift array access may allocate.
        private let slots: UnsafeMutablePointer<Int32>
        private let renders: UnsafeMutablePointer<Bool>
        private let tapCount: Int

        init(
            deviceUID: String,
            routes: [(index: Int, route: Route)],
            gains: UnsafeMutablePointer<Float>,
            peaks: UnsafeMutablePointer<Float>
        ) throws {
            tapCount = routes.count
            slots = .allocate(capacity: routes.count)
            renders = .allocate(capacity: routes.count)
            for (position, entry) in routes.enumerated() {
                slots[position] = Int32(entry.index)
                renders[position] = entry.route.isSilenced
            }

            do {
                for entry in routes {
                    // A stereo mixdown tap has one predictable format whatever the
                    // app plays, which is what keeps the mixing below trivial.
                    let description = CATapDescription(stereoMixdownOfProcesses: entry.route.processIDs)
                    description.name = "Kalfa · \(entry.route.name)"
                    description.isPrivate = true
                    description.muteBehavior = entry.route.isSilenced ? .mutedWhenTapped : .unmuted
                    var tapID = AudioObjectID(kAudioObjectUnknown)
                    let status = AudioHardwareCreateProcessTap(description, &tapID)
                    guard status == noErr else { throw MixerError.operation("tap", status) }
                    taps.append(tapID)
                }

                let aggregateDescription: [String: Any] = [
                    kAudioAggregateDeviceNameKey: "Kalfa Mixer",
                    kAudioAggregateDeviceUIDKey: "com.aliakpoyraz.kalfa.mixer.\(UUID().uuidString)",
                    kAudioAggregateDeviceIsPrivateKey: true,
                    kAudioAggregateDeviceTapAutoStartKey: true,
                ]
                let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID)
                guard aggregateStatus == noErr else { throw MixerError.operation("aggregate", aggregateStatus) }

                try AppAudioRouter.setCFArray([deviceUID as CFString], on: aggregateID, selector: kAudioAggregateDevicePropertyFullSubDeviceList)
                try AppAudioRouter.setCFArray(try taps.map(AppAudioRouter.tapUID), on: aggregateID, selector: kAudioAggregateDevicePropertyTapList)
                try AppAudioRouter.setCFString(deviceUID as CFString, on: aggregateID, selector: kAudioAggregateDevicePropertyMainSubDevice)

                let slots = slots
                let renders = renders
                let tapCount = tapCount
                let createStatus = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) {
                    _, inputData, _, outputData, _ in
                    AppAudioRouter.mix(
                        inputData: inputData,
                        outputData: outputData,
                        gains: gains,
                        peaks: peaks,
                        slots: slots,
                        renders: renders,
                        tapCount: tapCount
                    )
                }
                guard createStatus == noErr else { throw MixerError.operation("ioProc", createStatus) }
                guard let ioProcID else { throw MixerError.missingIOProc }
                let startStatus = AudioDeviceStart(aggregateID, ioProcID)
                guard startStatus == noErr else { throw MixerError.operation("start", startStatus) }
            } catch {
                stop()
                throw error
            }
        }

        deinit {
            stop()
            slots.deallocate()
            renders.deallocate()
        }

        func stop() {
            if aggregateID != kAudioObjectUnknown, let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
                self.ioProcID = nil
            }
            if aggregateID != kAudioObjectUnknown {
                AudioHardwareDestroyAggregateDevice(aggregateID)
                aggregateID = AudioObjectID(kAudioObjectUnknown)
            }
            for tap in taps { AudioHardwareDestroyProcessTap(tap) }
            taps.removeAll()
        }
    }

    // MARK: Real-time mixing

    /// Runs on the audio thread: no allocation, no locks, no Swift runtime calls
    /// beyond pointer arithmetic.
    private static func mix(
        inputData: UnsafePointer<AudioBufferList>,
        outputData: UnsafeMutablePointer<AudioBufferList>,
        gains: UnsafePointer<Float>,
        peaks: UnsafeMutablePointer<Float>,
        slots: UnsafePointer<Int32>,
        renders: UnsafePointer<Bool>,
        tapCount: Int
    ) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        let outputs = UnsafeMutableAudioBufferListPointer(outputData)

        for output in outputs {
            guard let data = output.mData else { continue }
            data.initializeMemory(as: UInt8.self, repeating: 0, count: Int(output.mDataByteSize))
        }

        let buffersPerTap = max(outputs.count, 1)
        for (inputIndex, input) in inputs.enumerated() {
            let tapIndex = inputIndex / buffersPerTap
            guard tapIndex < tapCount, let sourceData = input.mData else { continue }

            let slot = Int(slots[tapIndex])
            let gain = gains[slot]
            let source = sourceData.assumingMemoryBound(to: Float.self)
            let outputIndex = inputIndex % buffersPerTap

            var sampleCount = Int(input.mDataByteSize) / MemoryLayout<Float>.size
            var destination: UnsafeMutablePointer<Float>?
            if renders[tapIndex], outputIndex < outputs.count, let outputData = outputs[outputIndex].mData {
                sampleCount = min(sampleCount, Int(outputs[outputIndex].mDataByteSize) / MemoryLayout<Float>.size)
                destination = outputData.assumingMemoryBound(to: Float.self)
            }

            var peak: Float = 0
            for sample in 0..<sampleCount {
                let value = source[sample] * gain
                let magnitude = value < 0 ? -value : value
                if magnitude > peak { peak = magnitude }
                if let destination {
                    destination[sample] = max(-1, min(1, destination[sample] + value))
                }
            }
            if peak > peaks[slot] { peaks[slot] = peak }
        }
    }

    // MARK: CoreAudio plumbing

    static func defaultOutput() throws -> (id: AudioDeviceID, uid: String) {
        var property = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let deviceStatus = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &device)
        guard deviceStatus == noErr else { throw MixerError.operation("output", deviceStatus) }

        property = address(kAudioDevicePropertyDeviceUID)
        var uid: CFString?
        size = UInt32(MemoryLayout<CFString?>.size)
        let uidStatus = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(device, &property, 0, nil, &size, $0)
        }
        guard uidStatus == noErr, let uid else { throw MixerError.operation("outputUID", uidStatus) }
        return (device, uid as String)
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    fileprivate static func tapUID(_ id: AudioObjectID) throws -> CFString {
        var property = address(kAudioTapPropertyUID)
        var uid: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(id, &property, 0, nil, &size, $0)
        }
        guard status == noErr, let uid else { throw MixerError.operation("tapUID", status) }
        return uid
    }

    fileprivate static func setCFArray(_ values: [CFString], on object: AudioObjectID, selector: AudioObjectPropertySelector) throws {
        var property = address(selector)
        var value = values as CFArray
        let status = withUnsafePointer(to: &value) {
            AudioObjectSetPropertyData(object, &property, 0, nil, UInt32(MemoryLayout<CFArray>.size), $0)
        }
        guard status == noErr else { throw MixerError.operation("array", status) }
    }

    fileprivate static func setCFString(_ string: CFString, on object: AudioObjectID, selector: AudioObjectPropertySelector) throws {
        var property = address(selector)
        var value = string
        let status = withUnsafePointer(to: &value) {
            AudioObjectSetPropertyData(object, &property, 0, nil, UInt32(MemoryLayout<CFString>.size), $0)
        }
        guard status == noErr else { throw MixerError.operation("string", status) }
    }

    enum MixerError: Error, CustomStringConvertible {
        case operation(String, OSStatus)
        case missingIOProc

        var description: String {
            switch self {
            case let .operation(name, status): "\(name): \(status)"
            case .missingIOProc: "ioProc: missing"
            }
        }
    }
}
