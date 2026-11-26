import AppKit
import SwiftUI
import KalfaUI

/// The page someone opens when something is wrong: every row maps to a Kalfa
/// feature that can fail silently — a permission never granted, a monitor link
/// that quietly dropped to 4:2:2, a shortcut another app took — and carries the
/// button that fixes it. What needs attention is listed first.
struct HealthView: View {

    private let health = HealthService.shared
    @State private var ticker: Timer?

    var body: some View {
        Form {
            if !attention.isEmpty {
                Section(L10n.t("health.section.attention")) {
                    ForEach(attention) { row($0) }
                }
            }
            Section {
                ForEach(fine) { row($0) }
            } header: {
                HStack {
                    Text(L10n.t("health.section.fine"))
                    Spacer()
                    Button {
                        health.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.t("header.rescan"))
                }
            }
        }
        .kalfaForm()
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

    private var attention: [HealthService.Check] {
        health.checks.filter { $0.level == .problem || $0.level == .warning }
    }

    private var fine: [HealthService.Check] {
        health.checks.filter { $0.level == .ok || $0.level == .info }
    }

    private func row(_ check: HealthService.Check) -> some View {
        HStack(alignment: .top, spacing: KalfaDesign.m) {
            Image(systemName: icon(check.level))
                .foregroundStyle(tone(check.level).color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(KalfaDesign.bodyFont)
                Text(check.detail).kalfaFootnote()
            }

            Spacer(minLength: KalfaDesign.s)

            if let fixTitle = check.fixTitle, let fix = check.fix {
                Button(fixTitle, action: fix)
            }
        }
    }

    private func icon(_ level: HealthService.Level) -> String {
        switch level {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .problem: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func tone(_ level: HealthService.Level) -> KalfaTone {
        switch level {
        case .ok: return .ok
        case .warning: return .warn
        case .problem: return .bad
        case .info: return .neutral
        }
    }
}
