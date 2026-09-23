import SwiftUI

/// The panel's search box and its results.
///
/// Same catalogue as the floating palette, so anything Kalfa can do is reachable
/// by typing in either place. Inside the panel the results replace the dashboard
/// rather than opening a second surface.
struct PanelSearchField: View {
    @Binding var query: String
    var focus: FocusState<Bool>.Binding
    let shortcutLabel: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: KalfaDesign.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(L10n.t("home.command.placeholder"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused(focus)
                .onSubmit(onSubmit)
                .accessibilityLabel(L10n.t("home.command.placeholder"))

            if query.isEmpty {
                Text(shortcutLabel)
                    .font(KalfaDesign.captionFont.monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                    .accessibilityHidden(true)
            } else {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(L10n.t("home.command.clear"))
                .accessibilityLabel(L10n.t("home.command.clear"))
            }
        }
        .padding(.horizontal, KalfaDesign.m)
        .frame(height: 36)
        .kalfaSurface(radius: KalfaDesign.tileRadius)
    }
}

struct PanelSearchResults: View {
    let items: [CommandItem]
    let run: (CommandItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if items.isEmpty {
                VStack(spacing: KalfaDesign.s) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                    Text(L10n.t("home.noResults"))
                        .font(KalfaDesign.bodyFont)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
            } else {
                ForEach(items.prefix(8)) { item in
                    Button { run(item) } label: {
                        HStack(spacing: KalfaDesign.s) {
                            Image(systemName: item.icon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(item.tint)
                                .frame(width: 24, height: 24)
                                .background(item.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(KalfaDesign.bodyFont.weight(.medium))
                                    .lineLimit(1)
                                Text(item.detail)
                                    .font(KalfaDesign.captionFont)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: KalfaDesign.xs)
                        }
                        .padding(.horizontal, KalfaDesign.s)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if items.count > 8 {
                    Text(L10n.t("home.more", items.count - 8))
                        .font(KalfaDesign.captionFont)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, KalfaDesign.s)
                        .padding(.top, 2)
                }
            }
        }
        .padding(KalfaDesign.xs)
        .kalfaSurface()
    }
}
