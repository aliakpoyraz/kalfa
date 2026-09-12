import SwiftUI

/// The whole menu bar panel.
struct RootView: View {

    @Environment(DisplayCenter.self) private var center
    @State private var showingSettings = false
    @State private var showingSaveSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if let pending = center.pendingRevert {
                revertBanner(pending)
                Divider()
            }

            if center.screens.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(center.screens) { screen in
                            DisplayCardView(screen: screen)
                        }
                    }
                    .padding(14)
                }
                .frame(maxHeight: 460)
            }

            Divider()

            ProfilesSectionView(showingSaveSheet: $showingSaveSheet)
                .padding(14)

            if let message = center.statusMessage {
                Divider()
                statusLine(message)
            }

            Divider()

            footer
        }
        .frame(width: 380)
        .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
            SettingsView()
        }
        .sheet(isPresented: $showingSaveSheet) {
            SaveProfileView()
                .environment(center)
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Klapa")
                    .font(.headline)
                Text(arrangementSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if center.isApplying {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                center.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Ekranları yeniden tara")

            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Ayarlar")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var arrangementSummary: String {
        if center.screens.isEmpty { return "Ekran bulunamadı" }
        let count = center.screens.count
        let suffix = count == 1 ? "1 ekran" : "\(count) ekran"
        return center.isClamshell ? "Kapak kapalı · \(suffix)" : suffix
    }

    private var emptyState: some View {
        Text("Bağlı ekran okunamadı.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(24)
    }

    private func statusLine(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }

    /// Shown while an unproven mode is on screen. Wording assumes the reader may
    /// be squinting at a barely-legible display, so it leads with the question.
    private func revertBanner(_ pending: DisplayCenter.PendingRevert) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Görüntü düzgün mü?")
                .font(.subheadline.weight(.semibold))
            Text("\(pending.screenName) · \(pending.applied.summary)\n\(pending.secondsLeft) saniye içinde eski moda dönülecek.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Bu modu koru") { center.confirmPendingMode() }
                    .keyboardShortcut(.defaultAction)
                Button("Geri al") { Task { await center.revertPendingMode() } }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
    }

    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Klapa \(version)"
    }

    private var footer: some View {
        HStack {
            Text(versionLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Çık") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
