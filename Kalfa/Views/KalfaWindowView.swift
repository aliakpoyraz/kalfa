import AppKit
import EzDPIKit
import SwiftUI
import UpkeepKit
import KalfaUI

/// Kalfa's one window: everything that is set once and left alone.
///
/// Laid out the way System Settings is — a sidebar of subjects, each a grouped
/// form that stops growing at a readable width — because that is the shape
/// people already know how to read on this platform.
///
/// An AppKit window rather than a SwiftUI `Window` scene because it is opened
/// from places that have no SwiftUI environment: the command palette, a hotkey,
/// a `kalfa://` URL.
@MainActor
enum KalfaWindow {

    enum Section: String, CaseIterable, Identifiable {
        case displays, audio, desktop, power, upkeep, network, health, settings

        var id: String { rawValue }
        var title: String { L10n.t("window.section.\(rawValue)") }
        var subtitle: String { L10n.t("window.subtitle.\(rawValue)") }

        var symbol: String {
            switch self {
            case .displays: return "display"
            case .audio: return "speaker.wave.2"
            case .desktop: return "macwindow"
            case .power: return "bolt"
            case .upkeep: return "wrench.adjustable"
            case .network: return "network"
            case .health: return "stethoscope"
            case .settings: return "gearshape"
            }
        }

        /// The sidebar's three groups, in the order someone reaches for them.
        static let groups: [(key: String, sections: [Section])] = [
            ("window.group.mac", [.displays, .audio, .desktop, .power]),
            ("window.group.tools", [.upkeep, .network]),
            ("window.group.kalfa", [.health, .settings]),
        ]

        /// Accepts the page names of earlier versions too, so a saved
        /// `kalfa://window?section=dpi` shortcut keeps landing somewhere.
        init?(name: String) {
            switch name {
            case "system": self = .desktop
            case "dpi": self = .network
            case "about": self = .settings
            default: self.init(rawValue: name)
            }
        }
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
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.title = L10n.t("app.name")
        // The page says what it is; a second "Kalfa" above it says nothing.
        created.titleVisibility = .hidden
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

    private let health = HealthService.shared

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { router.section },
                set: { router.section = $0 ?? router.section }
            )) {
                ForEach(KalfaWindow.Section.groups, id: \.key) { group in
                    Section(L10n.t(group.key)) {
                        ForEach(group.sections) { section in
                            Label(section.title, systemImage: section.symbol)
                                .badge(section == .health ? issueCount : 0)
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
        .onAppear { health.refresh() }
    }

    private var issueCount: Int {
        health.checks.filter { $0.level == .problem || $0.level == .warning }.count
    }

    @ViewBuilder
    private func detail(_ section: KalfaWindow.Section) -> some View {
        switch section {
        case .displays:
            KalfaPage(section) { DisplaysPage() }
        case .audio:
            KalfaPage(section) { AudioPage() }
        case .desktop:
            KalfaPage(section) { DesktopPage().environment(scroll) }
        case .power:
            KalfaPage(section) { PowerPage() }
        case .upkeep:
            KalfaPage(section) { UpkeepPage() }
        case .network:
            KalfaPage(section) { NetworkPage() }
        case .health:
            KalfaPage(section) { HealthView() }
        case .settings:
            KalfaPage(section) { SettingsView().environment(center) }
        }
    }
}

// MARK: - Page chrome

/// One page of the window: the same title block on every page, then the
/// content, which brings its own scrolling.
///
/// The page never wraps its content in a `ScrollView`. A form or a list asked to
/// live inside another scroll view has no height to measure itself against and
/// collapses — the DPI site list once came out empty exactly this way.
struct KalfaPage<Content: View>: View {

    private let section: KalfaWindow.Section
    private let content: Content

    init(_ section: KalfaWindow.Section, @ViewBuilder content: () -> Content) {
        self.section = section
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(KalfaDesign.pageFont)
                Text(section.subtitle)
                    .font(KalfaDesign.bodyFont)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, KalfaDesign.pageInset)
            .padding(.top, KalfaDesign.s)
            .padding(.bottom, KalfaDesign.xs)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

extension View {
    /// The window's form: grouped like System Settings, and held to a width at
    /// which a label and its control are still next to each other.
    func kalfaForm() -> some View {
        formStyle(.grouped)
            .frame(maxWidth: KalfaDesign.formWidth, alignment: .leading)
    }

    /// A line of explanation under a control.
    func kalfaFootnote() -> some View {
        font(KalfaDesign.captionFont)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Displays

private struct DisplaysPage: View {

    @Environment(DisplayCenter.self) private var center
    @State private var showingSaveSheet = false

    private let brightness = BrightnessService.shared

    var body: some View {
        Form {
            if center.screens.isEmpty {
                Section {
                    Text(L10n.t("empty.displays"))
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(center.screens) { screen in
                Section {
                    DisplayRows(screen: screen)
                } header: {
                    DisplayHeader(screen: screen)
                }
            }

            Section {
                Toggle(L10n.t("brightness.belowZero"), isOn: Binding(
                    get: { brightness.allowsBelowZero },
                    set: { brightness.setAllowsBelowZero($0) }
                ))
                Picker(L10n.t("brightness.floor"), selection: Binding(
                    get: { brightness.floor },
                    set: { brightness.setFloor($0) }
                )) {
                    ForEach(BrightnessService.floorChoices, id: \.self) { value in
                        Text("%\(Int(value * 100))").tag(value)
                    }
                }
                Picker(L10n.t("brightness.method"), selection: Binding(
                    get: { brightness.method },
                    set: { brightness.setMethod($0) }
                )) {
                    ForEach(BrightnessService.Method.allCases) { method in
                        Text(L10n.t("brightness.method.\(method.rawValue)")).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                LabeledContent(L10n.t("brightness.reset")) {
                    Text(HotkeyService.shared.label(for: .resetDimming))
                        .font(KalfaDesign.bodyFont.monospaced())
                        .foregroundStyle(.secondary)
                    Button(L10n.t("brightness.lift")) { brightness.resetDimming() }
                        .disabled(!brightness.isDimming)
                }
            } header: {
                Text(L10n.t("brightness.section"))
            } footer: {
                Text(L10n.t("brightness.help")).kalfaFootnote()
            }

            Section(L10n.t("profiles")) {
                ProfilesSectionView(showingSaveSheet: $showingSaveSheet)
            }

            Section {
                HStack {
                    Button(L10n.t("header.rescan"), systemImage: "arrow.clockwise") {
                        center.refreshNow()
                        center.syncBrightness()
                    }
                    if center.isApplying {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    if let message = center.statusMessage {
                        Text(message).kalfaFootnote()
                    }
                }
            }
        }
        .kalfaForm()
        .onAppear { center.syncBrightness() }
        .sheet(isPresented: $showingSaveSheet) {
            SaveProfileView()
                .environment(center)
        }
    }
}

// MARK: - Upkeep

/// Disk, cleaning, uninstalling and repairs as one page with four modes.
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
            .fixedSize()

            // Each mode carries its own scroll view; see `KalfaPage`.
            switch mode {
            case .disk: DiskAnalysisView()
            case .clean: CleanupView()
            case .uninstall: UninstallView()
            case .repair: RepairsView()
            }
        }
        .padding(.horizontal, KalfaDesign.pageInset)
        .padding(.vertical, KalfaDesign.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Network

/// DNS and the DPI half on one page: both are about how this Mac reaches the
/// network, and neither is big enough to deserve the other's absence.
private struct NetworkPage: View {

    private let network = NetworkTools.shared

    var body: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.l) {
            VStack(alignment: .leading, spacing: KalfaDesign.s) {
                Text(L10n.t("dns"))
                    .font(KalfaDesign.headingFont)
                Picker("", selection: Binding(get: { network.dns }, set: { network.setDNS($0) })) {
                    ForEach(NetworkTools.DNSChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Text("\(network.dnsDetail)  \(L10n.t("dns.help"))").kalfaFootnote()
            }

            VStack(alignment: .leading, spacing: KalfaDesign.s) {
                Text(L10n.t("tab.dpi"))
                    .font(KalfaDesign.headingFont)
                EzDPIPanel()
                EzDPISettings()
            }
        }
        .padding(.horizontal, KalfaDesign.pageInset)
        .padding(.vertical, KalfaDesign.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
