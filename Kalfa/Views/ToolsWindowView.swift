import SwiftUI

/// The tools window: everything Kalfa can do that nobody needs daily.
///
/// These used to be eight collapsed rows inside the menu bar panel, where a
/// 392-point column had to hold a DNS picker, a timer and a folder chooser. They
/// are the same controls; they simply have room now, and moving them out is what
/// let the panel become a dashboard.
struct ToolsWindowView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("tools"))
                    .font(.title3.weight(.semibold))
                Text(L10n.t("tools.subtitle"))
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.secondary)
            }

            SystemTabView()

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 420)
        .background(.regularMaterial)
    }
}
