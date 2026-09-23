import AppKit
import SwiftUI
import UpkeepKit
import KalfaUI

/// Uninstalling: pick an app, see everything it leaves behind, confirm.
///
/// The leftover list is the whole point of the screen, so it is shown before
/// anything can be removed rather than summarised as a count. People say yes to
/// "remove 14 items" without reading; they read a list with their own files in it.
struct UninstallView: View {

    @ObservedObject private var service = Upkeep.uninstall
    @State private var query = ""
    @State private var confirming = false

    var body: some View {
        HStack(alignment: .top, spacing: KalfaDesign.m) {
            appList
            Divider()
            detail
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

    // MARK: App list

    private var appList: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.s) {
            TextField(L10n.t("upkeep.uninstall.search"), text: $query)
                .textFieldStyle(.roundedBorder)

            if service.isLoading {
                ProgressView().controlSize(.small)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(filtered) { app in
                        Button {
                            service.select(app)
                        } label: {
                            HStack(spacing: KalfaDesign.s) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(app.name)
                                        .font(KalfaDesign.bodyFont)
                                        .lineLimit(1)
                                    if app.isRunning {
                                        Text(L10n.t("upkeep.uninstall.running"))
                                            .font(KalfaDesign.captionFont)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Spacer(minLength: KalfaDesign.xs)
                                Text(Upkeep.bytes(app.size))
                                    .font(KalfaDesign.captionFont.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, KalfaDesign.xs)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background {
                            if service.selected?.path == app.path {
                                RoundedRectangle(cornerRadius: KalfaDesign.controlRadius, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.18))
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 230)
    }

    private var filtered: [InstalledApp] {
        guard !query.isEmpty else { return service.apps }
        return service.apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let app = service.selected {
            VStack(alignment: .leading, spacing: KalfaDesign.s) {
                Text(app.name).font(KalfaDesign.headingFont)
                Text(app.bundleID)
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.secondary)

                if service.leftovers.isEmpty {
                    ProgressView().controlSize(.small)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(service.leftovers) { leftover in
                                leftoverRow(leftover)
                            }
                        }
                    }
                }

                Divider()
                HStack {
                    Text(L10n.t("upkeep.uninstall.selected",
                                service.checkedCount,
                                Upkeep.bytes(service.checkedSize)))
                        .font(KalfaDesign.captionFont)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.t("upkeep.uninstall.action")) { confirming = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(service.checkedCount == 0 || app.isRunning)
                }
                if let error = service.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(KalfaDesign.captionFont)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            VStack {
                if let result = service.lastResult {
                    Label(result, systemImage: "checkmark.circle.fill")
                        .font(KalfaDesign.bodyFont)
                        .foregroundStyle(.green)
                }
                Text(L10n.t("upkeep.uninstall.hint"))
                    .font(KalfaDesign.bodyFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func leftoverRow(_ leftover: Leftover) -> some View {
        HStack(spacing: KalfaDesign.s) {
            Toggle("", isOn: Binding(
                get: { service.checked.contains(leftover.path) },
                set: { _ in service.toggle(leftover) }
            ))
            .labelsHidden()
            .disabled(!leftover.isRemovable)

            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.t("upkeep.kind.\(leftover.kind.rawValue)"))
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.secondary)
                Text(leftover.path)
                    .font(KalfaDesign.bodyFont)
                    .lineLimit(1)
                    .truncationMode(.head)
                    // A path outside the home folder needs an administrator, so
                    // it is shown for the record and cannot be selected.
                    .foregroundStyle(leftover.isRemovable ? .primary : .secondary)
            }
            Spacer(minLength: KalfaDesign.xs)
            Text(Upkeep.bytes(leftover.size))
                .font(KalfaDesign.captionFont.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
    }
}
