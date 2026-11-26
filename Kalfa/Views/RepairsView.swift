import SwiftUI
import UpkeepKit
import KalfaUI

/// The repairs list: five things that each fix one real symptom.
///
/// Deliberately absent: `purge` and anything sold as "free up RAM". macOS
/// already manages memory, and forcing it empty only makes the next access come
/// from disk — the classic fake speed-up button.
///
/// Tasks needing an administrator are badged before they are run, and the
/// password never reaches Kalfa: the AppleScript call raises the system's own
/// dialog. AppleScript error -128 means the person cancelled, which is not a
/// failure.

struct RepairsView: View {
    @ObservedObject private var service = Upkeep.optimize

    var body: some View {
        // Scrolls itself like the other three modes. Without it the page has no
        // height to size against: the split view measured the wrapped detail
        // texts at a sliver of width, the page grew to ~6000 pt and pushed the
        // whole window, sidebar included, off screen — it came out blank.
        ScrollView {
            list.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.s) {
            ForEach(service.tasks) { task in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: KalfaDesign.s) {
                        Text(L10n.t("repair.\(task.rawValue)"))
                            .font(KalfaDesign.bodyFont)
                        if task.needsAdmin {
                            Text(L10n.t("repair.admin"))
                                .font(KalfaDesign.captionFont)
                                .padding(.horizontal, KalfaDesign.xs)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(KalfaTone.warn.color.opacity(0.18))
                                )
                                .foregroundStyle(KalfaTone.warn.color)
                        }
                        Spacer(minLength: KalfaDesign.xs)

                        if service.running?.id == task.id {
                            ProgressView().controlSize(.small)
                        } else if service.succeeded(task) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(KalfaTone.ok.color)
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
                            .foregroundStyle(KalfaTone.warn.color)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}
