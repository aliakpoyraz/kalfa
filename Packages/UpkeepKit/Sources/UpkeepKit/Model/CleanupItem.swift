import Foundation

/// Temizlik adayı.
public struct CleanupItem: Sendable, Identifiable, Equatable {
    public var id: String { path }
    public var path: String
    public var displayName: String
    public var size: UInt64
    public var category: Category

    /// Varsayılan olarak işaretli gelir mi?
    ///
    /// İki sınıf var: yeniden üretilebilen şeyler (önbellek, günlük, derleme
    /// çıktısı) ve üretilemeyenler. İkinciler listelenir ama işaretlenmez —
    /// kullanıcı isterse seçer, araç onun adına karar vermez.
    public var recommended: Bool

    public enum Category: String, Sendable, CaseIterable {
        case caches, logs, savedState, crashReports
        case derivedData, deviceSupport, simulator
        case installers, projectArtifacts, trash
    }

    public init(path: String, displayName: String, size: UInt64,
                category: Category, recommended: Bool) {
        self.path = path
        self.displayName = displayName
        self.size = size
        self.category = category
        self.recommended = recommended
    }
}
