import Foundation

enum LogLevel: String, Codable {
    case info = "BILGI", warn = "UYARI", error = "HATA"
}

struct LogEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let level: LogLevel
    let message: String
}

/// Hem diske hem hafızaya yazan basit günlük. Arayüzdeki Günlük sekmesi
/// hafızadaki listeyi gösterir, disk kopyası çökme sonrası teşhis içindir.
@MainActor
final class Log: ObservableObject {
    static let shared = Log()
    @Published private(set) var entries: [LogEntry] = []
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private init() {}

    func info(_ m: String) { add(.info, m) }
    func warn(_ m: String) { add(.warn, m) }
    func error(_ m: String) { add(.error, m) }

    private func add(_ level: LogLevel, _ message: String) {
        let entry = LogEntry(id: UUID(), date: Date(), level: level, message: message)
        entries.append(entry)
        // Hafızada sınırsız büyümesin; disk kopyası zaten tam.
        if entries.count > 500 { entries.removeFirst(entries.count - 500) }
        // Diske yazma işini Log.write yapar; buradan çağrılan yol yalnızca
        // arayüz listesini besler.
    }

    nonisolated private static func appendToDisk(_ level: LogLevel, _ message: String) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        writeLine("\(f.string(from: Date())) [\(level.rawValue)] \(message)\n")
    }

    nonisolated static func writeLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        let path = Paths.appLog
        if let handle = try? FileHandle(forWritingTo: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: path)
        }
    }

    /// Diske ANINDA yazar, arayüz listesini sonra günceller. Kapanış sırasında
    /// çağrılan satırlar aksi halde süreç ölmeden diske ulaşmıyordu.
    nonisolated static func write(_ level: LogLevel, _ message: String) {
        appendToDisk(level, message)
        Task { @MainActor in
            switch level {
            case .info: Log.shared.info(message)
            case .warn: Log.shared.warn(message)
            case .error: Log.shared.error(message)
            }
        }
    }
}
