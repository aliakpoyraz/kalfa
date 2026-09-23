import AppKit
import SwiftUI
import UpkeepKit

/// The size tree, one directory at a time.
///
/// Not a treemap. A treemap looks impressive and is hard to act on: the reader
/// has to hunt for the rectangle, and rectangles under a few percent are
/// unclickable. A sorted list with a proportional bar answers "what is big and
/// where is it" in one read, and every row is a target.
struct DiskAnalysisView: View {

    @ObservedObject private var disk = Upkeep.disk
    @State private var pendingTrash: DiskNode?

    var body: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.s) {
            controls

            if disk.isScanning {
                scanning
            } else if disk.root == nil {
                Text(L10n.t("upkeep.disk.hint"))
                    .font(KalfaDesign.bodyFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                trail
                rows
            }

            if let error = disk.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.orange)
            }
        }
        .confirmationDialog(
            L10n.t("upkeep.trash.confirm", pendingTrash?.name ?? ""),
            isPresented: Binding(get: { pendingTrash != nil },
                                 set: { if !$0 { pendingTrash = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.t("upkeep.trash.action"), role: .destructive) {
                if let node = pendingTrash { disk.trash(node) }
                pendingTrash = nil
            }
            Button(L10n.t("cancel"), role: .cancel) { pendingTrash = nil }
        } message: {
            // Says where the files go, because "delete" and "move to Trash" are
            // different promises and only one of them can be taken back.
            Text(L10n.t("upkeep.trash.explain"))
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: KalfaDesign.s) {
            Button(disk.isScanning ? L10n.t("upkeep.disk.scanning") : L10n.t("upkeep.disk.scan")) {
                disk.start()
            }
            .disabled(disk.isScanning)
            .buttonStyle(.borderedProminent)

            if disk.isScanning {
                Button(L10n.t("cancel")) { disk.cancel() }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if let root = disk.root {
                Text(L10n.t("upkeep.disk.total",
                            Upkeep.bytes(root.size),
                            root.fileCount))
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var scanning: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.xs) {
            ProgressView()
                .controlSize(.small)
            Text(L10n.t("upkeep.disk.progress",
                        disk.progress.scannedFiles,
                        Upkeep.bytes(disk.progress.scannedBytes)))
                .font(KalfaDesign.bodyFont)
            Text(disk.progress.currentPath)
                .font(KalfaDesign.captionFont)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Trail

    private var trail: some View {
        HStack(spacing: KalfaDesign.xs) {
            ForEach(Array(disk.trail.enumerated()), id: \.offset) { index, node in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button(node.name) { disk.jump(to: index) }
                    .buttonStyle(.borderless)
                    .font(KalfaDesign.captionFont)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Rows

    private var rows: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(disk.rows(), id: \.path) { node in
                    DiskRow(node: node,
                            share: disk.share(of: node),
                            open: { disk.open(node) },
                            reveal: { NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "") },
                            trash: { pendingTrash = node })
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct DiskRow: View {
    let node: DiskNode
    let share: Double
    let open: () -> Void
    let reveal: () -> Void
    let trash: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: KalfaDesign.s) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(node.isDirectory ? Color.accentColor : .secondary)
                .frame(width: 16)

            Text(node.name)
                .font(KalfaDesign.bodyFont)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: KalfaDesign.s)

            if hovering {
                Button(action: reveal) { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
                    .help(L10n.t("upkeep.reveal"))
                Button(action: trash) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help(L10n.t("upkeep.trash.action"))
            }

            Text(Upkeep.bytes(node.size))
                .font(KalfaDesign.captionFont.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, KalfaDesign.s)
        .background(alignment: .leading) {
            // The bar is the row, not a separate column: at a glance the eye
            // reads length, and giving it its own strip would waste the width
            // that the name needs.
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: KalfaDesign.controlRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(hovering ? 0.22 : 0.12))
                    .frame(width: max(geometry.size.width * share, 2))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: open)
    }
}
