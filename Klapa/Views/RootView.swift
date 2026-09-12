import SwiftUI

/// The whole menu bar panel.
struct RootView: View {

    @Environment(DisplayCenter.self) private var center
    @State private var showingSettings = false
    @State private var showingAbout = false
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
                // Laid out directly rather than in a ScrollView: inside a
                // MenuBarExtra window a ScrollView resolves to zero ideal height
                // and silently swallows its content. Nobody has enough displays
                // for the panel to need scrolling anyway.
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(center.screens) { screen in
                        DisplayCardView(screen: screen)
                    }
                }
                .padding(14)
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
        // Rebuilds the panel when the language changes; SwiftUI cannot see into
        // the strings bundle on its own.
        .id(center.settings.language.rawValue)
        .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
            SettingsView()
                .environment(center)
        }
        .popover(isPresented: $showingAbout, arrowEdge: .bottom) {
            AboutView()
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
                Text(L10n.t("app.name"))
                    .font(.headline)
                Text(layoutSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if center.isApplying {
                ProgressView()
                    .controlSize(.small)
            }

            Button { center.refreshNow() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(L10n.t("header.rescan"))

            Button { showingSettings.toggle() } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(L10n.t("header.settings"))

            Button { showingAbout.toggle() } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help(L10n.t("header.about"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var layoutSummary: String {
        let count = center.screens.count
        guard count > 0 else { return L10n.t("header.noDisplays") }
        let displays = count == 1
            ? L10n.t("header.displayCount.one")
            : L10n.t("header.displayCount.many", count)
        return center.isClamshell ? "\(L10n.t("header.clamshell")) · \(displays)" : displays
    }

    private var emptyState: some View {
        Text(L10n.t("empty.displays"))
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(24)
    }

    /// Shown while an unproven mode is on screen. Wording leads with the question
    /// because the reader may be squinting at a barely-legible display.
    private func revertBanner(_ pending: DisplayCenter.PendingRevert) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("revert.title"))
                .font(.subheadline.weight(.semibold))
            Text(L10n.t(
                "revert.body",
                pending.screenName, pending.applied.summary, pending.secondsLeft
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L10n.t("revert.keep")) { center.confirmPendingMode() }
                    .keyboardShortcut(.defaultAction)
                Button(L10n.t("revert.undo")) { Task { await center.revertPendingMode() } }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
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

    private var footer: some View {
        HStack {
            Text(versionLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button(L10n.t("footer.quit")) { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Klapa \(version)"
    }
}
