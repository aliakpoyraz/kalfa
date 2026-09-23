import AppKit
import Carbon.HIToolbox
import Observation

/// System-wide keyboard shortcuts.
///
/// Carbon's `RegisterEventHotKey` rather than an `NSEvent` global monitor: a
/// monitor only observes, so the keystroke still reaches whatever is in front —
/// pressing the tiling shortcut would also type into the document. A registered
/// hot key is consumed.
///
/// Every binding is editable and stored in `UserDefaults`. The handler for an
/// action is installed once at launch and survives re-binding, so the recorder
/// only has to swap the key.
@MainActor
@Observable
final class HotkeyService {

    static let shared = HotkeyService()

    /// A recorded key combination. `modifiers` is a Carbon mask, not an
    /// `NSEvent.ModifierFlags` raw value; the label is kept alongside so the
    /// panel never has to translate a key code back into a glyph.
    struct Binding: Codable, Equatable {
        var keyCode: UInt32
        var modifiers: UInt32
        var label: String
    }

    /// The things a shortcut can do.
    enum Action: UInt32, CaseIterable, Identifiable {
        case commandPalette = 1
        case muteInput
        case tileLeft
        case tileRight
        case tileTop
        case tileBottom
        case tileCenter
        case tileFull

        var id: UInt32 { rawValue }

        /// Shipped combinations. Each uses a modifier set macOS itself leaves alone.
        var defaultBinding: Binding {
            let control = UInt32(controlKey)
            let option = UInt32(optionKey)
            let command = UInt32(cmdKey)
            switch self {
            // Not ⌥⌘Space: macOS itself owns that one (Finder's Spotlight window).
            case .commandPalette: return .init(keyCode: UInt32(kVK_ANSI_K), modifiers: option | command, label: "⌥⌘K")
            case .muteInput:      return .init(keyCode: UInt32(kVK_ANSI_M), modifiers: option | command, label: "⌥⌘M")
            case .tileLeft:       return .init(keyCode: UInt32(kVK_LeftArrow), modifiers: control | option, label: "⌃⌥←")
            case .tileRight:      return .init(keyCode: UInt32(kVK_RightArrow), modifiers: control | option, label: "⌃⌥→")
            case .tileTop:        return .init(keyCode: UInt32(kVK_UpArrow), modifiers: control | option, label: "⌃⌥↑")
            case .tileBottom:     return .init(keyCode: UInt32(kVK_DownArrow), modifiers: control | option, label: "⌃⌥↓")
            case .tileCenter:     return .init(keyCode: UInt32(kVK_ANSI_C), modifiers: control | option, label: "⌃⌥C")
            case .tileFull:       return .init(keyCode: UInt32(kVK_Return), modifiers: control | option, label: "⌃⌥↩")
            }
        }

        var titleKey: String {
            switch self {
            case .commandPalette: return "hotkey.commandPalette"
            case .muteInput:      return "hotkey.muteInput"
            case .tileLeft:       return "hotkey.tileLeft"
            case .tileRight:      return "hotkey.tileRight"
            case .tileTop:        return "hotkey.tileTop"
            case .tileBottom:     return "hotkey.tileBottom"
            case .tileCenter:     return "hotkey.tileCenter"
            case .tileFull:       return "hotkey.tileFull"
            }
        }
    }

    /// Why a shortcut is not answering.
    enum Problem: Equatable {
        /// Another application owns the combination; Carbon refused to register it.
        case taken
        /// Two Kalfa actions are bound to the same keys.
        case duplicate(Action)
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var registered: [UInt32: EventHotKeyRef] = [:]
    private var handlerInstalled = false
    private let defaults = UserDefaults.standard
    private static let bindingsKey = "hotkeyBindings"

    /// Actions that could not take their key, for the health panel and the
    /// recorder to show. Observed, so the UI updates the moment a re-bind fails.
    private(set) var problems: [Action: Problem] = [:]

    private init() {}

    // MARK: Bindings

    /// `nil` means the action is deliberately switched off.
    func binding(for action: Action) -> Binding? {
        guard let stored = storedBindings()[String(action.rawValue)] else { return action.defaultBinding }
        return stored.isDisabled ? nil : stored.binding
    }

    func label(for action: Action) -> String {
        binding(for: action)?.label ?? "—"
    }

    func setBinding(_ binding: Binding?, for action: Action) {
        var stored = storedBindings()
        stored[String(action.rawValue)] = StoredBinding(binding: binding ?? action.defaultBinding, isDisabled: binding == nil)
        writeBindings(stored)
        applyAll()
    }

    func resetBinding(for action: Action) {
        var stored = storedBindings()
        stored.removeValue(forKey: String(action.rawValue))
        writeBindings(stored)
        applyAll()
    }

    func isDefault(_ action: Action) -> Bool {
        storedBindings()[String(action.rawValue)] == nil
    }

    // MARK: Registration

    /// Installs what an action does. Called once per action at launch; re-binding
    /// reuses the handler stored here.
    func install(_ action: Action, run: @escaping () -> Void) {
        handlers[action.rawValue] = run
        apply(action)
    }

    func unregisterAll() {
        for action in Action.allCases { unregister(action) }
    }

    private func applyAll() {
        for action in Action.allCases { apply(action) }
    }

    private func apply(_ action: Action) {
        installHandlerIfNeeded()
        unregister(action)
        problems[action] = nil

        guard handlers[action.rawValue] != nil, let binding = binding(for: action) else { return }

        // A combination used twice inside Kalfa registers only once, and the
        // second action would silently do nothing — name it instead.
        if let clash = Action.allCases.first(where: { other in
            other != action && registered[other.rawValue] != nil && self.binding(for: other) == binding
        }) {
            problems[action] = .duplicate(clash)
            return
        }

        let id = EventHotKeyID(signature: OSType(0x4B_4C_46_41), id: action.rawValue)  // "KLFA"
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            id,
            GetEventDispatcherTarget(),
            0,
            &reference
        )
        // A shortcut another app already owns simply does not register. Not worth
        // an alert, but the health panel reads `problems` and says so.
        guard status == noErr, let reference else {
            problems[action] = .taken
            Log.display.notice("hotkey \(binding.label, privacy: .public) is taken by something else")
            return
        }
        registered[action.rawValue] = reference
    }

    private func unregister(_ action: Action) {
        if let reference = registered.removeValue(forKey: action.rawValue) {
            UnregisterEventHotKey(reference)
        }
    }

    // MARK: Storage

    private struct StoredBinding: Codable {
        var binding: Binding
        var isDisabled: Bool
    }

    private func storedBindings() -> [String: StoredBinding] {
        guard let data = defaults.data(forKey: Self.bindingsKey),
              let decoded = try? JSONDecoder().decode([String: StoredBinding].self, from: data)
        else { return [:] }
        return decoded
    }

    private func writeBindings(_ value: [String: StoredBinding]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.bindingsKey)
    }

    // MARK: Dispatch

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &id
            )
            guard status == noErr else { return status }
            MainActor.assumeIsolated { HotkeyService.shared.fire(id.id) }
            return noErr
        }, 1, &spec, nil, nil)
    }

    fileprivate func fire(_ rawValue: UInt32) {
        handlers[rawValue]?()
    }
}

// MARK: - Recording

extension HotkeyService.Binding {

    /// Builds a binding from a key-down event, or `nil` when the combination is
    /// unusable: a bare key with no modifier would swallow ordinary typing
    /// system-wide, and Carbon refuses shift-only combinations anyway.
    init?(event: NSEvent) {
        let carbon = Self.carbonModifiers(event.modifierFlags)
        let isFunctionKey = Self.functionKeyLabels[event.keyCode] != nil
        guard carbon != 0 || isFunctionKey else { return nil }
        guard event.keyCode != UInt16(kVK_Escape) else { return nil }

        keyCode = UInt32(event.keyCode)
        modifiers = carbon
        label = Self.modifierGlyphs(event.modifierFlags) + Self.keyLabel(for: event)
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        return mask
    }

    /// Menu order, the order macOS itself prints modifiers in.
    private static func modifierGlyphs(_ flags: NSEvent.ModifierFlags) -> String {
        var glyphs = ""
        if flags.contains(.control) { glyphs += "⌃" }
        if flags.contains(.option) { glyphs += "⌥" }
        if flags.contains(.shift) { glyphs += "⇧" }
        if flags.contains(.command) { glyphs += "⌘" }
        return glyphs
    }

    private static func keyLabel(for event: NSEvent) -> String {
        if let known = functionKeyLabels[event.keyCode] { return known }
        let characters = event.charactersIgnoringModifiers ?? ""
        // Option produces the accented character rather than the key's own letter,
        // so the unmodified string is the one worth showing.
        return characters.isEmpty ? "?" : characters.uppercased()
    }

    /// Keys whose character is invisible or misleading.
    private static let functionKeyLabels: [UInt16: String] = [
        UInt16(kVK_Return): "↩",
        UInt16(kVK_ANSI_KeypadEnter): "⌤",
        UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_Home): "↖",
        UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞",
        UInt16(kVK_PageDown): "⇟",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
    ]
}
