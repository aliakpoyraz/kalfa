import SwiftUI
import AppKit

struct LogTab: View {
    @ObservedObject private var log = Log.shared
    @EnvironmentObject var l10n: L10n

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(T("Kayıt klasörünü aç", "Open log folder")) {
                    NSWorkspace.shared.selectFile(Paths.appLog.path,
                                                  inFileViewerRootedAtPath: Paths.logs.path)
                }
                Spacer()
            }
            ScrollViewReader { proxy in
                List(log.entries) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.date, format: .dateTime.hour().minute().second())
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(entry.level.rawValue)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(color(for: entry.level))
                        Text(entry.message).font(.caption)
                    }
                    .id(entry.id)
                }
                .onChange(of: log.entries.count) {
                    if let last = log.entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .padding(4)
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .warn: return .orange
        case .error: return .red
        }
    }
}
