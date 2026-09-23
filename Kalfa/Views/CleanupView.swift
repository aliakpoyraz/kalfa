import SwiftUI
import UpkeepKit
import KalfaUI

/// Deep clean: what can go, grouped by what kind of thing it is.
///
/// Nothing is removed without a tick, and the ticks that arrive pre-set are only
/// on things the machine rebuilds by itself — caches, logs, derived data.
/// Installers, device support and build output are listed unticked: they are
/// regenerable in theory and expensive in practice, so that call is the reader's.
struct CleanupView: View {

    @ObservedObject private var service = Upkeep.cleanup
    @State private var confirming = false
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.s) {
            header

            if service.isScanning {
                VStack(alignment: .leading, spacing: KalfaDesign.xs) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("upkeep.clean.scanning"))
                        .font(KalfaDesign.captionFont)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if service.items.isEmpty {
                Text(L10n.t("upkeep.clean.hint"))
                    .font(KalfaDesign.bodyFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }

            footer
        }
        .confirmationDialog(
            L10n.t("upkeep.clean.confirm",
                   service.checkedCount,
                   Upkeep.bytes(service.checkedSize)),
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(L10n.t("upkeep.trash.action"), role: .destructive) { service.clean() }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t(service.checked.contains("\(NSHomeDirectory())/.Trash")
                        ? "upkeep.clean.explain.trash"
                        : "upkeep.trash.explain"))
        }
    }

    private var header: some View {
        HStack {
            Button(service.isScanning
                   ? L10n.t("upkeep.clean.scanning")
                   : L10n.t("upkeep.clean.scan")) {
                service.scan()
            }
            .buttonStyle(.borderedProminent)
            .disabled(service.isScanning)

            Spacer()

            if let result = service.lastResult {
                Label(result, systemImage: "checkmark.circle.fill")
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.green)
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: KalfaDesign.xs) {
                ForEach(service.categories, id: \.rawValue) { category in
                    categorySection(category)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func categorySection(_ category: CleanupItem.Category) -> some View {
        let items = service.items(in: category)
        let total = items.reduce(UInt64(0)) { $0 &+ $1.size }
        let isOpen = expanded.contains(category.rawValue)

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: KalfaDesign.s) {
                Button {
                    if isOpen { expanded.remove(category.rawValue) }
                    else { expanded.insert(category.rawValue) }
                } label: {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    service.toggleCategory(category)
                } label: {
                    Text(L10n.t("upkeep.cat.\(category.rawValue)"))
                        .font(KalfaDesign.headingFont)
                }
                .buttonStyle(.plain)

                Text("\(items.count)")
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.tertiary)

                Spacer()
                Text(Upkeep.bytes(total))
                    .font(KalfaDesign.captionFont.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            if isOpen {
                ForEach(items) { item in
                    HStack(spacing: KalfaDesign.s) {
                        Toggle("", isOn: Binding(
                            get: { service.checked.contains(item.path) },
                            set: { _ in service.toggle(item) }
                        ))
                        .labelsHidden()

                        Text(category == .trash
                             ? L10n.t("upkeep.cat.trash")
                             : item.displayName)
                            .font(KalfaDesign.bodyFont)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: KalfaDesign.xs)
                        Text(Upkeep.bytes(item.size))
                            .font(KalfaDesign.captionFont.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, KalfaDesign.l)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(L10n.t("upkeep.clean.selected",
                        service.checkedCount,
                        Upkeep.bytes(service.checkedSize)))
                .font(KalfaDesign.captionFont)
                .foregroundStyle(.secondary)
            Spacer()
            if let error = service.lastError {
                Text(error)
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.orange)
            }
            Button(L10n.t("upkeep.clean.action")) { confirming = true }
                .buttonStyle(.borderedProminent)
                .disabled(service.checkedCount == 0)
        }
    }
}
