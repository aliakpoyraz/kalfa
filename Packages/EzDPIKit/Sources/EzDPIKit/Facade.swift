import AppKit
import Combine
import SwiftUI
import KalfaUI

/// What the host app is allowed to touch.
///
/// Everything else in this module stays internal, exactly as it was when this
/// code was the ezDPI app: the host drives a lifecycle and shows two views, and
/// nothing about the engine, the rules or the proxy leaks across the boundary.
@MainActor
public enum EzDPI {

    /// Starts rule evaluation and recovers a proxy left behind by a crash.
    /// Call once, after the app finishes launching.
    public static func start() {
        Supervisor.shared.start()
    }

    /// Puts the system proxy back and stops the engine. Must run before the
    /// process goes away — skipping it leaves the machine pointed at a dead port
    /// with no internet, which is the one failure the user cannot debug.
    public static func shutdown() {
        Supervisor.shared.shutdown()
    }

    /// `ezdpi://on | off | auto | relaunch?bundle=<id>`, kept working so the
    /// Shortcuts and Raycast entries people already made still drive the app.
    @discardableResult
    public static func handle(url: URL) -> Bool {
        guard url.scheme == "ezdpi" else { return false }
        let action = (url.host ?? url.path.replacingOccurrences(of: "/", with: "")).lowercased()
        switch action {
        case "on": Supervisor.shared.mode = .forceOn
        case "off": Supervisor.shared.mode = .forceOff
        case "auto": Supervisor.shared.mode = .auto
        case "relaunch":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            guard let bundleID = items?.first(where: { $0.name == "bundle" })?.value else {
                Log.write(.warn, "relaunch çağrısında bundle parametresi yok.")
                return false
            }
            Task { await Supervisor.shared.relaunchWithProxy(bundleID: bundleID) }
        default:
            Log.write(.warn, "Bilinmeyen bağlantı: \(url.absoluteString)")
            return false
        }
        return true
    }

    /// Kept so the host's existing call still compiles, and so a config written
    /// by an older version keeps its recorded choice. There is nothing to do
    /// any more: both halves read the same `L10n`, whose language is the one the
    /// person picked in Kalfa's settings. The DPI half used to carry a second
    /// language picker that set a second stored value.
    public static func setLanguage(turkish: Bool?) {
        ConfigStore.shared.config.settings.language = turkish.map { $0 ? .tr : .en } ?? .system
    }

    /// Whether the engine is up, for the menu bar icon.
    public static var isActive: Bool { Supervisor.shared.isActive }

    /// How the DPI panel reaches its own page in the host's window.
    ///
    /// It used to call `openSettings()` and rely on a SwiftUI `Settings` scene.
    /// That scene is gone — the DPI settings are a section of the one Kalfa
    /// window now — and the environment action silently does nothing when no
    /// such scene exists, so the button in the panel had quietly stopped
    /// working. A closure the host fills in cannot rot the same way: it is nil
    /// or it is wired.
    public static var showSettings: (() -> Void)?

    /// Where the rules and the log live. The About page offers both, and this
    /// is the only reason the host needs to know these paths exist.
    public static func revealConfigFolder() {
        NSWorkspace.shared.selectFile(Paths.config.path, inFileViewerRootedAtPath: Paths.support.path)
    }

    public static func revealLogFolder() {
        NSWorkspace.shared.selectFile(Paths.appLog.path, inFileViewerRootedAtPath: Paths.logs.path)
    }

    /// One line for the About page: which engine, listening where.
    public static var engineSummary: String {
        guard let port = Supervisor.shared.activePort else { return "—" }
        return "\(Supervisor.shared.store.config.settings.listenHost):\(port)"
    }

    /// How the DPI half decides to run: by rules, always, or never. A scene can
    /// carry one of these along with a display arrangement.
    public enum Mode: String, CaseIterable, Sendable {
        case auto, on, off
    }

    public static var mode: Mode {
        get {
            switch Supervisor.shared.mode {
            case .auto: return .auto
            case .forceOn: return .on
            case .forceOff: return .off
            }
        }
        set {
            switch newValue {
            case .auto: Supervisor.shared.mode = .auto
            case .on: Supervisor.shared.mode = .forceOn
            case .off: Supervisor.shared.mode = .forceOff
            }
        }
    }
}

/// Observable mirror of the running state, so the host's menu bar label can
/// change without the host seeing `Supervisor` itself.
@MainActor
public final class EzDPIStatus: ObservableObject {
    @Published public private(set) var isActive = false

    private var cancellable: AnyCancellable?

    public init() {
        isActive = Supervisor.shared.isActive
        cancellable = Supervisor.shared.objectWillChange.sink { [weak self] _ in
            // objectWillChange fires before the value lands.
            DispatchQueue.main.async { self?.isActive = Supervisor.shared.isActive }
        }
    }
}

/// The DPI tab of the host's menu bar panel.
@MainActor
public struct EzDPIPanel: View {
    public init() {}

    public var body: some View {
        MenuPanel()
            .id(L10n.language.rawValue)
            .environmentObject(ConfigStore.shared)
            .environmentObject(Supervisor.shared)
                }
}

/// The DPI settings window: sites, rules, test, log, about.
@MainActor
public struct EzDPISettings: View {
    @StateObject private var diagnostics = Diagnostics()

    public init() {}

    public var body: some View {
        SettingsView()
            .id(L10n.language.rawValue)
            .environmentObject(ConfigStore.shared)
            .environmentObject(Supervisor.shared)
            .environmentObject(diagnostics)
                }
}
