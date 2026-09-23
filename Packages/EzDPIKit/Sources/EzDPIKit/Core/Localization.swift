import Foundation
import SwiftUI

enum Language: String, Codable, CaseIterable, Identifiable {
    case system, tr, en
    var id: String { rawValue }
}

/// İki dil için ayrı .strings dosyası taşımak yerine metin çiftleri kodun
/// içinde duruyor: çeviri, kullanıldığı yerin yanında görünür ve anahtar
/// kayması olmaz. Üçüncü dil gelirse burası dosya tabanlıya çevrilir.
@MainActor
final class L10n: ObservableObject {
    static let shared = L10n()
    @Published var language: Language = .system

    /// Sistem dili Türkçe ise Türkçe, değilse İngilizce.
    var isTurkish: Bool {
        switch language {
        case .tr: return true
        case .en: return false
        case .system:
            return (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("tr")
        }
    }

    func s(_ tr: String, _ en: String) -> String { isTurkish ? tr : en }
}

/// Kısa çağrı: T("Ayarlar", "Settings")
@MainActor
func T(_ tr: String, _ en: String) -> String { L10n.shared.s(tr, en) }
