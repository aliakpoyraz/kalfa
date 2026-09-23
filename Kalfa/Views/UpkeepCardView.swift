import AppKit
import SwiftUI
import UpkeepKit

/// Upkeep inside the panel: disk, cleaning, uninstalling and repairs.
///
/// Four modes behind one segmented control rather than four cards, because the
/// panel is a menu and a menu that outgrows the screen becomes a thing you
/// scroll instead of read.
///
/// **No ScrollView anywhere below.** Inside a MenuBarExtra window a ScrollView
/// resolves to zero ideal height and silently swallows its content, so every
/// list here is capped at a row count the panel can hold; the window is where
/// the full tree lives.
struct UpkeepCardView: View {

    @State private var mode: Mode = .disk

    enum Mode: String, CaseIterable {
        case disk, clean, uninstall, repairs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.s) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.rawValue) { mode in
                    Text(L10n.t("upkeep.mode.\(mode.rawValue)")).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .disk: CompactDiskView()
            case .clean: CompactCleanView()
            case .uninstall: CompactUninstallView()
            case .repairs: RepairsView()
            }
        }
        .padding(.vertical, KalfaDesign.xs)
    }
}

// MARK: - Disk

private struct CompactDiskView: View {
    @ObservedObject private var disk = Upkeep.disk
    private let rowLimit = 10

    var body: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.s) {
            HStack(spacing: KalfaDesign.s) {
                Button(disk.isScanning ? L10n.t("upkeep.disk.scanning") : L10n.t("upkeep.disk.scan")) {
                    disk.start()
                }
                .disabled(disk.isScanning)
                .controlSize(.small)

                if disk.isScanning {
                    Button(L10n.t("cancel")) { disk.cancel() }
                        .controlSize(.small)
                }
                Spacer()
                if disk.root != nil {
                    Button(L10n.t("upkeep.inWindow")) { UpkeepWindow.show() }
                        .buttonStyle(.borderless)
                        .font(KalfaDesign.captionFont)
                }
            }

            if disk.isScanning {
                Text(L10n.t("upkeep.disk.progress",
                            disk.progress.scannedFiles,
                            Upkeep.bytes(disk.progress.scannedBytes)))
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.secondary)
            } else if let current = disk.current {
                HStack(spacing: KalfaDesign.xs) {
                    if disk.trail.count > 1 {
                        Button {
                            disk.back()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                    }
                    Text(current.name)
                        .font(KalfaDesign.captionFont)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    Text(Upkeep.bytes(current.size))
                        .font(KalfaDesign.captionFont.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ForEach(disk.rows(limit: rowLimit), id: \.path) { node in
                    CompactBarRow(
                        title: node.name,
                        detail: Upkeep.bytes(node.size),
                        share: disk.share(of: node),
                        symbol: node.isDirectory ? "folder.fill" : "doc"
                    ) {
                        if node.isDirectory { disk.open(node) }
                    }
                }

                if (disk.current?.children.count ?? 0) > rowLimit {
                    Text(L10n.t("upkeep.more", (disk.current?.children.count ?? 0) - rowLimit))
                        .font(KalfaDesign.captionFont)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text(L10n.t("upkeep.disk.hint"))
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Clean

private struct CompactCleanView: View {
    @ObservedObject private var cleanup = Upkeep.cleanup
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.s) {
            HStack {
                Button(cleanup.isScanning
                       ? L10n.t("upkeep.clean.scanning")
                       : L10n.t("upkeep.clean.scan")) {
                    cleanup.scan()
                }
                .disabled(cleanup.isScanning)
                .controlSize(.small)
                Spacer()
                if let result = cleanup.lastResult {
                    Text(result)
                        .font(KalfaDesign.captionFont)
                        .foregroundStyle(.green)
                }
            }

            if cleanup.isScanning {
                Text(L10n.t("upkeep.clean.scanning"))
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.secondary)
            } else if cleanup.items.isEmpty {
                Text(L10n.t("upkeep.clean.hint"))
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Categories, not files: nine groups fit the panel, two hundred
                // individual paths do not. Per-file picking lives in the window.
                ForEach(cleanup.categories, id: \.rawValue) { category in
                    let items = cleanup.items(in: category)
                    let total = items.reduce(UInt64(0)) { $0 &+ $1.size }
                    let allOn = items.allSatisfy { cleanup.checked.contains($0.path) }

                    Button {
                        cleanup.toggleCategory(category)
                    } label: {
                        HStack(spacing: KalfaDesign.s) {
                            Image(systemName: allOn ? "checkmark.square.fill" : "square")
                                .foregroundStyle(allOn ? Color.accentColor : .secondary)
                            Text(L10n.t("upkeep.cat.\(category.rawValue)"))
                                .font(KalfaDesign.bodyFont)
                                .lineLimit(1)
                            Spacer(minLength: KalfaDesign.xs)
                            Text(Upkeep.bytes(total))
                                .font(KalfaDesign.captionFont.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Text(L10n.t("upkeep.clean.selected",
                                cleanup.checkedCount,
                                Upkeep.bytes(cleanup.checkedSize)))
                        .font(KalfaDesign.captionFont)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.t("upkeep.inWindow")) { UpkeepWindow.show() }
                        .buttonStyle(.borderless)
                        .font(KalfaDesign.captionFont)
                    Button(L10n.t("upkeep.clean.action")) { confirming = true }
                        .controlSize(.small)
                        .disabled(cleanup.checkedCount == 0)
                }
            }
        }
        .confirmationDialog(
            L10n.t("upkeep.clean.confirm", cleanup.checkedCount, Upkeep.bytes(cleanup.checkedSize)),
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(L10n.t("upkeep.trash.action"), role: .destructive) { cleanup.clean() }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t(cleanup.checked.contains("\(NSHomeDirectory())/.Trash")
                        ? "upkeep.clean.explain.trash"
                        : "upkeep.trash.explain"))
        }
    }
}

// MARK: - Uninstall

private struct CompactUninstallView: View {
    @ObservedObject private var service = Upkeep.uninstall
    @State private var query = ""
    @State private var confirming = false
    private let rowLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.s) {
            if let app = service.selected {
                detail(app)
            } else {
                list
            }
        }
        .onAppear { if service.apps.isEmpty { service.loadApps() } }
        .confirmationDialog(
            L10n.t("upkeep.uninstall.confirm", service.selected?.name ?? ""),
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(L10n.t("upkeep.trash.action"), role: .destructive) { service.uninstall() }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("upkeep.uninstall.explain",
                        service.checkedCount,
                        Upkeep.bytes(service.checkedSize)))
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.s) {
            HStack {
                TextField(L10n.t("upkeep.uninstall.search"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                if service.isLoading {
                    ProgressView().controlSize(.small)
                }
            }

            if let result = service.lastResult {
                Label(result, systemImage: "checkmark.circle.fill")
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.green)
            }

            ForEach(filtered.prefix(rowLimit)) { app in
                Button {
                    service.select(app)
                } label: {
                    HStack(spacing: KalfaDesign.s) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(app.name)
                            .font(KalfaDesign.bodyFont)
                            .lineLimit(1)
                        if app.isRunning {
                            Text(L10n.t("upkeep.uninstall.running"))
                                .font(KalfaDesign.captionFont)
                                .foregroundStyle(.orange)
                        }
                        Spacer(minLength: KalfaDesign.xs)
                        Text(Upkeep.bytes(app.size))
                            .font(KalfaDesign.captionFont.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if filtered.count > rowLimit {
                Text(L10n.t("upkeep.more", filtered.count - rowLimit))
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Drill-down rather than a second pane: 392 points cannot hold a list and a
    /// detail side by side without both becoming unreadable.
    private func detail(_ app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: KalfaDesign.s) {
            HStack(spacing: KalfaDesign.xs) {
                Button {
                    service.clearSelection()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                Text(app.name).font(KalfaDesign.headingFont)
                Spacer()
                Text(Upkeep.bytes(app.size))
                    .font(KalfaDesign.captionFont.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if service.leftovers.isEmpty {
                ProgressView().controlSize(.small)
            } else {
                ForEach(service.leftovers.prefix(rowLimit)) { leftover in
                    Button {
                        service.toggle(leftover)
                    } label: {
                        HStack(spacing: KalfaDesign.s) {
                            Image(systemName: service.checked.contains(leftover.path)
                                  ? "checkmark.square.fill" : "square")
                                .foregroundStyle(tint(for: leftover))
                            Text(L10n.t("upkeep.kind.\(leftover.kind.rawValue)"))
                                .font(KalfaDesign.bodyFont)
                                .lineLimit(1)
                            Spacer(minLength: KalfaDesign.xs)
                            Text(Upkeep.bytes(leftover.size))
                                .font(KalfaDesign.captionFont.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!leftover.isRemovable)
                }

                if service.leftovers.count > rowLimit {
                    Text(L10n.t("upkeep.more", service.leftovers.count - rowLimit))
                        .font(KalfaDesign.captionFont)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack {
                Text(L10n.t("upkeep.uninstall.selected",
                            service.checkedCount,
                            Upkeep.bytes(service.checkedSize)))
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.t("upkeep.uninstall.action")) { confirming = true }
                    .controlSize(.small)
                    .disabled(service.checkedCount == 0 || app.isRunning)
            }

            if let error = service.lastError {
                Text(error)
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var filtered: [InstalledApp] {
        guard !query.isEmpty else { return service.apps }
        return service.apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// Three states in one glyph: ticked, untouched, and out of reach. The last
    /// one is a path outside the home folder, which needs an administrator.
    private func tint(for leftover: Leftover) -> Color {
        guard leftover.isRemovable else { return Color.secondary.opacity(0.5) }
        return service.checked.contains(leftover.path) ? .accentColor : .secondary
    }
}

// MARK: - Repairs

/// Named "repairs", not "optimise": each of these fixes a specific symptom the
/// reader can recognise. There is no button here that claims to make the Mac
/// faster in general, because no such button honestly exists.
private struct RepairsView: View {
    @ObservedObject private var service = Upkeep.optimize

    var body: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.s) {
            ForEach(service.tasks) { task in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: KalfaDesign.s) {
                        Text(L10n.t("repair.\(task.rawValue)"))
                            .font(KalfaDesign.bodyFont)
                        if task.needsAdmin {
                            Text(L10n.t("repair.admin"))
                                .font(KalfaDesign.captionFont)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(Color.orange.opacity(0.18))
                                )
                                .foregroundStyle(.orange)
                        }
                        Spacer(minLength: KalfaDesign.xs)

                        if service.running?.id == task.id {
                            ProgressView().controlSize(.small)
                        } else if service.succeeded(task) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button(L10n.t("repair.run")) { service.run(task) }
                                .controlSize(.small)
                                .disabled(service.running != nil)
                        }
                    }
                    Text(L10n.t("repair.\(task.rawValue).detail"))
                        .font(KalfaDesign.captionFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = service.failure(task) {
                        Text(error)
                            .font(KalfaDesign.captionFont)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}

// MARK: - Shared row

/// A row whose background bar encodes the share. Same grammar as the window's
/// disk rows so the two read as one feature in two sizes.
private struct CompactBarRow: View {
    let title: String
    let detail: String
    let share: Double
    let symbol: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: KalfaDesign.s) {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 13)
                Text(title)
                    .font(KalfaDesign.bodyFont)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: KalfaDesign.xs)
                Text(detail)
                    .font(KalfaDesign.captionFont.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, KalfaDesign.xs)
            .background(alignment: .leading) {
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: KalfaDesign.controlRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(hovering ? 0.22 : 0.12))
                        .frame(width: max(geometry.size.width * share, 2))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
