import CoreAudio
import Foundation
import Observation

/// Output and input device switching, plus the volume each device was last left
/// at.
///
/// macOS keeps one system volume and re-uses it across devices, so going from
/// headphones at 20% to the monitor's speakers means the room gets the same 20%
/// — or, the other way round, a full-volume monitor setting lands in your ears.
/// Kalfa remembers a level per device and restores it on the way back.
@MainActor
@Observable
final class AudioService {

    static let shared = AudioService()

    struct Device: Identifiable, Hashable {
        let id: AudioDeviceID
        let uid: String
        let name: String
    }

    /// Speakers and microphones are the same objects in CoreAudio, told apart
    /// only by which scope has channels; everything here is written once and
    /// pointed at one scope or the other.
    enum Direction {
        case output
        case input

        var scope: AudioObjectPropertyScope {
            self == .output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
        }

        var defaultSelector: AudioObjectPropertySelector {
            self == .output
                ? kAudioHardwarePropertyDefaultOutputDevice
                : kAudioHardwarePropertyDefaultInputDevice
        }
    }

    private(set) var outputs: [Device] = []
    private(set) var inputs: [Device] = []
    private(set) var currentOutput: Device?
    private(set) var currentInput: Device?

    /// 0...1 for whichever device is selected right now.
    var volume: Double {
        get { currentVolume }
        set { setVolume(newValue, direction: .output) }
    }

    var inputVolume: Double {
        get { currentInputVolume }
        set { setVolume(newValue, direction: .input) }
    }

    /// Plenty of microphones — AirPods among them — report a level but refuse to
    /// take a new one. The slider is disabled rather than lying.
    var canSetInputVolume: Bool {
        guard let device = currentInput else { return false }
        return Self.isVolumeSettable(device.id, direction: .input)
    }

    /// Whether the microphone is muted right now.
    ///
    /// macOS has no system-wide microphone mute — every meeting app mutes only
    /// itself — so this is the real thing: the input device's own mute, or its
    /// level driven to zero on the devices that have no mute property.
    private(set) var isInputMuted = false

    private var currentVolume: Double = 0
    private var currentInputVolume: Double = 0
    /// Level to put back when unmuting a device with no mute property.
    private var levelBeforeMute: Double?
    private let defaults: UserDefaults
    private static let memoryKey = "audioVolumeByUID"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refresh()
        observeSystemChanges()
    }

    // MARK: Reading

    func refresh() {
        outputs = Self.devices(direction: .output)
        inputs = Self.devices(direction: .input)

        currentOutput = outputs.first { $0.id == Self.defaultDeviceID(.output) }
        currentInput = inputs.first { $0.id == Self.defaultDeviceID(.input) }

        currentVolume = currentOutput.map { Self.readVolume($0.id, direction: .output) } ?? 0
        currentInputVolume = currentInput.map { Self.readVolume($0.id, direction: .input) } ?? 0

        if let input = currentInput {
            isInputMuted = Self.readMute(input.id) ?? (levelBeforeMute != nil && currentInputVolume == 0)
        } else {
            isInputMuted = false
        }
    }

    // MARK: Microphone mute

    func toggleInputMute() {
        setInputMuted(!isInputMuted)
    }

    func setInputMuted(_ muted: Bool) {
        guard let device = currentInput else { return }

        if Self.writeMute(muted, to: device.id) {
            isInputMuted = muted
            currentInputVolume = Self.readVolume(device.id, direction: .input)
            return
        }

        // No mute property: fall back to the level, remembering what to restore.
        if muted {
            levelBeforeMute = currentInputVolume
            setVolume(0, direction: .input)
        } else {
            setVolume(levelBeforeMute ?? 0.5, direction: .input)
            levelBeforeMute = nil
        }
        isInputMuted = muted
    }

    // MARK: Switching

    /// Switches the system device, parking the old one's level first so coming
    /// back to it sounds the way it was left.
    func select(_ device: Device, direction: Direction = .output) {
        let current = direction == .output ? currentOutput : currentInput
        if let current, current.id != device.id {
            remember(volume: direction == .output ? currentVolume : currentInputVolume, for: current.uid)
        }
        guard Self.setDefaultDevice(device.id, direction: direction) else { return }

        let level = rememberedVolume(for: device.uid) ?? Self.readVolume(device.id, direction: direction)
        if rememberedVolume(for: device.uid) != nil {
            Self.writeVolume(level, to: device.id, direction: direction)
        }

        if direction == .output {
            currentOutput = device
            currentVolume = level
        } else {
            currentInput = device
            currentInputVolume = level
        }
    }

    /// Used when a scene names a device that may or may not be plugged in.
    @discardableResult
    func selectDevice(uid: String, direction: Direction = .output) -> Bool {
        let list = direction == .output ? outputs : inputs
        guard let device = list.first(where: { $0.uid == uid }) else { return false }
        select(device, direction: direction)
        return true
    }

    private func setVolume(_ value: Double, direction: Direction) {
        let clamped = min(max(value, 0), 1)
        let device = direction == .output ? currentOutput : currentInput
        if direction == .output { currentVolume = clamped } else { currentInputVolume = clamped }
        guard let device else { return }
        Self.writeVolume(clamped, to: device.id, direction: direction)
        remember(volume: clamped, for: device.uid)
    }

    // MARK: Per-device memory

    private func remember(volume: Double, for uid: String) {
        var map = defaults.dictionary(forKey: Self.memoryKey) as? [String: Double] ?? [:]
        map[uid] = volume
        defaults.set(map, forKey: Self.memoryKey)
    }

    private func rememberedVolume(for uid: String) -> Double? {
        (defaults.dictionary(forKey: Self.memoryKey) as? [String: Double])?[uid]
    }

    // MARK: Change notifications

    /// Plugging in headphones or waking a monitor changes both the device list
    /// and the default device behind our back; without listening, the panel shows
    /// a device that is no longer there.
    private func observeSystemChanges() {
        let selectors = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice,
        ]
        for selector in selectors {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main
            ) { _, _ in
                MainActor.assumeIsolated { AudioService.shared.refresh() }
            }
        }
    }

    // MARK: CoreAudio

    private static func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private static func devices(direction: Direction) -> [Device] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasChannels(id, direction: direction),
                  let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName)
            else { return nil }
            return Device(id: id, uid: uid, name: name)
        }
    }

    /// Every device shows up in the system list whichever way it points. A
    /// device with no channels in this direction is one we must not offer here.
    private static func hasChannels(_ id: AudioDeviceID, direction: Direction) -> Bool {
        var address = address(kAudioDevicePropertyStreamConfiguration, direction.scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else {
            return false
        }

        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    private static func defaultDeviceID(_ direction: Direction) -> AudioDeviceID {
        var address = address(direction.defaultSelector)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private static func setDefaultDevice(_ id: AudioDeviceID, direction: Direction) -> Bool {
        var address = address(direction.defaultSelector)
        var value = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &value
        ) == noErr
    }

    /// Volume lives on the main element for most devices and on the individual
    /// channels for the rest; an aggregate or a USB interface commonly has no
    /// main element at all.
    private static func readVolume(_ id: AudioDeviceID, direction: Direction) -> Double {
        if let value = scalar(id, direction: direction, element: kAudioObjectPropertyElementMain) {
            return value
        }
        let channels = [
            scalar(id, direction: direction, element: 1),
            scalar(id, direction: direction, element: 2),
        ].compactMap { $0 }
        guard !channels.isEmpty else { return 0 }
        return channels.reduce(0, +) / Double(channels.count)
    }

    private static func writeVolume(_ value: Double, to id: AudioDeviceID, direction: Direction) {
        if setScalar(id, direction: direction, element: kAudioObjectPropertyElementMain, value) { return }
        _ = setScalar(id, direction: direction, element: 1, value)
        _ = setScalar(id, direction: direction, element: 2, value)
    }

    private static func readMute(_ id: AudioDeviceID) -> Bool? {
        var address = address(kAudioDevicePropertyMute, Direction.input.scope)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    @discardableResult
    private static func writeMute(_ muted: Bool, to id: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyMute, Direction.input.scope)
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(id, &address),
              AudioObjectIsPropertySettable(id, &address, &settable) == noErr,
              settable.boolValue
        else { return false }

        var value = UInt32(muted ? 1 : 0)
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(id, &address, 0, nil, size, &value) == noErr
    }

    static func isVolumeSettable(_ id: AudioDeviceID, direction: Direction) -> Bool {
        [kAudioObjectPropertyElementMain, 1].contains { element in
            var address = address(kAudioDevicePropertyVolumeScalar, direction.scope, element)
            var settable = DarwinBoolean(false)
            return AudioObjectHasProperty(id, &address)
                && AudioObjectIsPropertySettable(id, &address, &settable) == noErr
                && settable.boolValue
        }
    }

    private static func scalar(
        _ id: AudioDeviceID,
        direction: Direction,
        element: AudioObjectPropertyElement
    ) -> Double? {
        var address = address(kAudioDevicePropertyVolumeScalar, direction.scope, element)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    @discardableResult
    private static func setScalar(
        _ id: AudioDeviceID,
        direction: Direction,
        element: AudioObjectPropertyElement,
        _ value: Double
    ) -> Bool {
        var address = address(kAudioDevicePropertyVolumeScalar, direction.scope, element)
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(id, &address),
              AudioObjectIsPropertySettable(id, &address, &settable) == noErr,
              settable.boolValue
        else { return false }

        var scalar = Float32(value)
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(id, &address, 0, nil, size, &scalar) == noErr
    }
}
