import Foundation

/// Localisation with an in-app override.
///
/// `Bundle.main.localizedString` alone would follow the system language and
/// nothing else. Kalfa lets someone pick Turkish or English independently,
/// because the language a person wants to read technical display terminology in
/// is not always the language their Mac is set to.
public enum L10n {

    public enum Language: String, CaseIterable, Identifiable {
        case system
        case turkish = "tr"
        case english = "en"

        public var id: String { rawValue }

        /// Shown in its own language, the way language pickers are expected to read.
        public var nativeName: String {
            switch self {
            case .system: return L10n.t("language.system")
            case .turkish: return "Türkçe"
            case .english: return "English"
            }
        }
    }

    public static let defaultsKey = "language"



    public static var language: Language {
        get {
            Language(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            cache.reset()
        }
    }

    // MARK: Lookup

    public static func t(_ key: String) -> String {
        cache.bundle().localizedString(forKey: key, value: key, table: nil)
    }

    public static func t(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: t(key), locale: Locale.current, arguments: arguments)
    }

    /// Resolving the override bundle means a directory lookup, and strings are
    /// fetched on every view body evaluation.
    private static let cache = BundleCache()

    private final class BundleCache: @unchecked Sendable {
        private let lock = NSLock()
        private var resolved: Bundle?

        func bundle() -> Bundle {
            lock.lock()
            defer { lock.unlock() }
            if let resolved { return resolved }

            let bundle: Bundle
            switch L10n.language {
            case .system:
                bundle = .main
            case .turkish, .english:
                let code = L10n.language.rawValue
                bundle = Bundle.main.path(forResource: code, ofType: "lproj")
                    .flatMap(Bundle.init(path:)) ?? .main
            }
            resolved = bundle
            return bundle
        }

        func reset() {
            lock.lock()
            resolved = nil
            lock.unlock()
        }
    }
}

extension L10n.Language {
    /// How the DPI half words the same choice: nil means "follow the system".
    public var prefersTurkish: Bool? {
        switch self {
        case .system: return nil
        case .turkish: return true
        case .english: return false
        }
    }
}
