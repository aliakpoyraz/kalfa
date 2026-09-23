import AppKit
import SwiftUI

/// The floating search box, opened by a shortcut from anywhere.
///
/// A panel of its own rather than the menu bar popover: the popover only exists
/// while the menu bar item is clicked, and the point of this window is to reach
/// Kalfa without aiming at the menu bar at all.
@MainActor
final class CommandPalette {

    static let shared = CommandPalette()

    /// Handed over by the panel once SwiftUI has built it. Without it the
    /// palette still works — it simply lists no display or scene entries.
    weak var center: DisplayCenter?

    private var panel: NSPanel?

    private init() {}

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        // On the screen the pointer is on, a third of the way down: centred looks
        // right on one display and lost on a six-monitor desk.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(
                NSPoint(
                    x: frame.midX - size.width / 2,
                    y: frame.midY + frame.height * 0.12 - size.height / 2
                )
            )
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 92),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // A hosting *controller* rather than a hosting view: the window then
        // follows SwiftUI's own size, so the result list is not clipped to
        // whatever height the panel happened to be created with.
        let view = CommandPaletteView { [weak self] in self?.hide() }
        panel.contentViewController = NSHostingController(rootView: view)
        panel.setContentSize(panel.contentViewController?.view.fittingSize ?? NSSize(width: 560, height: 92))
        return panel
    }

    /// A panel refuses key status by default, and a search box that cannot be
    /// typed into is not a search box.
    private final class KeyablePanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }
}

struct CommandPaletteView: View {

    let close: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @State private var feedback: String?
    @State private var monitor: Any?
    @FocusState private var focused: Bool

    private var items: [CommandItem] {
        CommandCatalog.match(
            query,
            in: CommandCatalog.items(center: CommandPalette.shared.center) { message in
                feedback = message
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field

            if !items.isEmpty {
                Divider()
                list
            } else {
                Divider()
                Text(L10n.t("home.noResults"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
        }
        .onAppear {
            focused = true
            installMonitor()
        }
        .onDisappear(perform: removeMonitor)
        .onChange(of: query) { selection = 0 }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(L10n.t("palette.placeholder"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($focused)
                .onSubmit(runSelection)

            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(40).enumerated()), id: \.element.id) { index, item in
                        row(item, isSelected: index == selection)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture { run(item) }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 320)
            .onChange(of: selection) { proxy.scrollTo(selection, anchor: .center) }
        }
    }

    private func row(_ item: CommandItem, isSelected: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.tint)
                .frame(width: 28, height: 28)
                .background(item.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.callout.weight(.medium))
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "return")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isSelected ? Color.accentColor.opacity(0.16) : .clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    /// Arrow keys and Escape never reach SwiftUI while a text field has focus,
    /// so the palette reads them before the field does.
    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            switch Int(event.keyCode) {
            case 125:  // down
                selection = min(selection + 1, max(items.count - 1, 0))
                return nil
            case 126:  // up
                selection = max(selection - 1, 0)
                return nil
            case 53:  // escape
                close()
                return nil
            default:
                return event
            }
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func runSelection() {
        guard items.indices.contains(selection) else { return }
        run(items[selection])
    }

    private func run(_ item: CommandItem) {
        item.run()
        query = ""
        selection = 0
        close()
    }
}
