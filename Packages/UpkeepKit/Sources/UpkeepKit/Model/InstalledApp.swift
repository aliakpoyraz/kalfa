import Foundation

/// Kurulu bir uygulama.
public struct InstalledApp: Sendable, Identifiable, Equatable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var bundleID: String
    public var size: UInt64
    /// Şu an çalışıyor mu? Çalışan uygulamayı kaldırmak yarım iş bırakır.
    public var isRunning: Bool

    public init(name: String, path: String, bundleID: String, size: UInt64, isRunning: Bool) {
        self.name = name
        self.path = path
        self.bundleID = bundleID
        self.size = size
        self.isRunning = isRunning
    }
}

/// Uygulamanın geride bıraktığı tek bir dosya ya da klasör.
public struct Leftover: Sendable, Identifiable, Equatable {
    public var id: String { path }
    public var path: String
    public var size: UInt64
    public var kind: Kind
    /// Çöp kutusuna taşınabilir mi? Ev dizini dışındakiler (sistem geneli
    /// LaunchDaemon'ları gibi) yönetici hakkı ister; listelenir ama seçilemez.
    public var isRemovable: Bool

    public enum Kind: String, Sendable {
        case bundle          // uygulamanın kendisi
        case support         // Application Support
        case caches
        case preferences
        case container
        case savedState
        case logs
        case launchAgent
        case webData
        case scripts
    }

    public init(path: String, size: UInt64, kind: Kind, isRemovable: Bool) {
        self.path = path
        self.size = size
        self.kind = kind
        self.isRemovable = isRemovable
    }
}
