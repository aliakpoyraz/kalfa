import AppKit
import EzDPIKit
import SwiftUI
import UpkeepKit
import KalfaUI

/// Kalfa's one window.
///
/// Everything that is not a daily switch lives here: the display list with room
/// to read it, the system tools, the upkeep work, the DPI rules, the health page
/// and the preferences. There used to be six separate windows and popovers for
/// this, and the cost was not screen space — it was that nobody could remember
/// which of them held what.
///
/// An AppKit window rather than a SwiftUI `Window` scene because it is opened
/// from places that have no SwiftUI environment: the command palette, a hotkey,
/// a `kalfa://` URL.
@MainActor
enum KalfaWindow {

    enum Section: String, CaseIterable, Identifiable {
        case displays, audio, system, upkeep, dpi, health, settings, about

        var id: String { rawValue }
        var title: String { L10n.t("window.section.\(rawValue)") }

        var symbol: String {
            switch self {
            case .displays: return "display"
            case .audio: return "speaker.wave.2.fill"
            case .system: return "slider.horizontal.3"
            case .upkeep: return "wrench.adjustable"
            case .dpi: return "lock.shield"
            case .health: return "stethoscope"
            case .settings: return "gearshape"
            case .about: return "info.circle"
            }
        }

        var role: KalfaRole {
            switch self {
            case .displays: return .display
            case .audio: return .audio
            case .system, .settings, .about: return .neutral
            case .upkeep: return .tools
            case .dpi: return .dpi
            case .health: return .alert
            }
        }

        /// The sidebar's three groups, in the order someone reaches for them.
        static let groups: [(key: String, sections: [Section])] = [
            ("window.group.mac", [.displays, .audio, .system]),
            ("window.group.care", [.upkeep, .health]),
            ("window.group.kalfa", [.dpi, .settings, .about]),
        ]
    }

    @MainActor
    final class Router: ObservableObject {
        @Published var section: Section = .displays
    }

    static let router = Router()
    private static var window: NSWindow?

    static func show(_ section: Section = .displays) {
        router.section = section

        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.title = L10n.t("app.name")
        created.titlebarAppearsTransparent = true
        created.isReleasedWhenClosed = false
        created.setFrameAutosaveName("KalfaWindow")
        created.center()
        created.contentView = NSHostingView(
            rootView: KalfaWindowView()
                .environmentObject(router)
                .environment(DisplayCenter.shared)
                .environment(ScrollService.shared)
        )
        window = created

        NSApp.activate(ignoringOtherApps: true)
        created.makeKeyAndOrderFront(nil)
    }
}

struct KalfaWindowView: View {

    @EnvironmentObject private var router: KalfaWindow.Router
    @Environment(DisplayCenter.self) private var center
    @Environment(ScrollService.self) private var scroll

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { router.section },
                set: { router.section = $0 ?? router.section }
            )) {
                ForEach(KalfaWindow.Section.groups, id: \.key) { group in
                    Section(L10n.t(group.key)) {
                        ForEach(group.sections) { section in
                            Label {
                                Text(section.title)
                            } icon: {
                                Image(systemName: section.symbol)
                                    .foregroundStyle(section.role.tint)
                            }
                            .tag(section)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            detail(router.section)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 720, minHeight: 480)
        // The strings bundle is invisible to SwiftUI; without this the window
        // keeps its old language until it is closed and opened again.
        .id(center.settings.language.rawValue)
    }

    @ViewBuilder
    private func detail(_ section: KalfaWindow.Section) -> some View {
        switch section {
        case .displays:
            page(section) { DisplaysPage() }
        case .audio:
            page(section) { AudioTabView() }
        case .system:
            page(section) { SystemTabView() }
        case .upkeep:
            // Its own lists scroll; an outer ScrollView would leave them nothing
            // to size against.
            page(section, scrolls: false) { UpkeepPage() }
        case .dpi:
            page(section, scrolls: false) { EzDPISettings() }
        case .health:
            HealthView()
        case .settings:
            page(section) {
                SettingsView()
                    .environment(center)
                    .environment(scroll)
            }
        case .about:
            page(section) { AboutView() }
        }
    }

    /// A titled page.
    ///
    /// `scrolls` is not a style choice. A `List` or a `ScrollView` asked to live
    /// inside another `ScrollView` has no height to measure itself against and
    /// collapses — the DPI site list came out empty exactly this way. Pages
    /// whose content scrolls itself get the title and nothing else.
    @ViewBuilder
    private func page<Content: View>(
        _ section: KalfaWindow.Section,
        scrolls: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let body = VStack(alignment: .leading, spacing: KalfaDesign.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .font(.title3.weight(.semibold))
                Text(L10n.t("window.subtitle.\(section.rawValue)"))
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(KalfaDesign.l)

        if scrolls {
            ScrollView { body }
        } else {
            body.frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Displays

/// The display list with room to breathe: the same cards as the panel, but the
/// window is not 392 points wide, so nothing has to be abbreviated.
private struct DisplaysPage: View {
    @Environment(DisplayCenter.self) private var center
    @State private var showingSaveSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.s) {
            if center.screens.isEmpty {
                Text(L10n.t("empty.displays"))
                    .font(KalfaDesign.bodyFont)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(center.screens) { screen in
                    DisplayCardView(screen: screen)
                }
            }

            HStack {
                Button(L10n.t("header.rescan"), systemImage: "arrow.clockwise") {
                    center.refreshNow()
                }
                if center.isApplying {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }
            .font(KalfaDesign.captionFont)

            if let message = center.statusMessage {
                Text(message)
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ProfilesSectionView(showingSaveSheet: $showingSaveSheet)
                .padding(.top, KalfaDesign.m)
        }
        .sheet(isPresented: $showingSaveSheet) {
            SaveProfileView()
                .environment(center)
        }
    }
}

// MARK: - Upkeep

/// Disk, cleaning, uninstalling and repairs as one page with four modes.
///
/// These were three tabs in a window of their own and four segments in a panel
/// card at the same time; the two copies had already drifted apart — the window
/// never got the repairs the card had.
private struct UpkeepPage: View {

    private enum Mode: String, CaseIterable, Identifiable {
        case disk, clean, uninstall, repair
        var id: String { rawValue }
        var title: String { L10n.t("upkeep.tab.\(rawValue)") }
    }

    @State private var mode: Mode = .disk

    var body: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.m) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .disk: DiskAnalysisView()
            case .clean: CleanupView()
            case .uninstall: UninstallView()
            case .repair: RepairsView()
            }
        }
    }
}
