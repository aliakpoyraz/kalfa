import AppKit
import SwiftUI
import KalfaUI

/// The page someone opens when something is wrong: every row maps to a Kalfa
/// feature that can fail silently — a permission never granted, a monitor link
/// that quietly dropped to 4:2:2, a shortcut another app took — and carries the
/// button that fixes it. Read top to bottom rather than poked at, which is why
/// it is a section of the window and not a card in the panel.
struct HealthView: View {

    private let health = HealthService.shared
    @State private var ticker: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(health.checks) { check in
                        row(check)
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            health.refresh()
            // Permissions are granted in another app; without a poll the page
            // keeps claiming a permission is missing after it was just given.
            ticker = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                Task { @MainActor in health.refresh() }
            }
        }
        .onDisappear {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("health.title"))
                    .font(.title3.weight(.semibold))
                Text(L10n.t("health.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                health.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(L10n.t("header.rescan"))
        }
        .padding(16)
    }

    private func row(_ check: HealthService.Check) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon(check.level))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color(check.level))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(.callout.weight(.medium))
                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let fixTitle = check.fixTitle, let fix = check.fix {
                Button(fixTitle, action: fix)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kalfaSurface(tint: color(check.level))
    }

    private func icon(_ level: HealthService.Level) -> String {
        switch level {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .problem: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func color(_ level: HealthService.Level) -> Color {
        switch level {
        case .ok: return .green
        case .warning: return .orange
        case .problem: return .red
        case .info: return .secondary
        }
    }
}
