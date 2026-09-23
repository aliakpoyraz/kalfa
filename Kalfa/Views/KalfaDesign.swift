import SwiftUI

/// The panel's visual language.
///
/// Three rules hold the redesign together:
///
/// 1. **Everything live is visible without opening anything.** Toggles are tiles
///    that carry their own state; nothing binary hides behind a disclosure arrow.
/// 2. **One grammar per kind of thing.** A tile is a switch, a card is a subject
///    you can open, a row is a setting inside one. No fourth pattern.
/// 3. **System colours only.** Kalfa follows macOS appearance and contrast
///    settings rather than maintaining a palette of its own; role tints are the
///    standard ones people already read (red for microphone, orange for awake).
enum KalfaDesign {

    static let panelWidth: CGFloat = 392

    // Spacing scale. Four steps, used everywhere; no ad-hoc paddings.
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let edge: CGFloat = 14

    static let tileRadius: CGFloat = 11
    static let cardRadius: CGFloat = 13
    static let controlRadius: CGFloat = 7

    // Type scale. Four sizes; anything else is a mistake, not a decision.
    static let titleFont = Font.system(size: 15, weight: .semibold)
    static let headingFont = Font.system(size: 13, weight: .semibold)
    static let bodyFont = Font.system(size: 12)
    static let captionFont = Font.system(size: 11)

    /// Short enough not to be in the way, long enough to be seen. Halved when the
    /// reader has asked for reduced motion.
    static let motion = Animation.easeOut(duration: 0.18)
}

/// What a control is about.
///
/// Five roles, not eleven. Colour names the *subject* — screens are blue, sound
/// is purple, the protection half is green, something wanting attention is
/// orange, everything else is neutral. Whether a control is on is carried by the
/// tint being filled in at all, so an eleventh hue bought nothing except a panel
/// that looked like a box of highlighters.
enum KalfaRole {
    case neutral, display, audio, dpi, alert

    var tint: Color {
        switch self {
        case .neutral: return .secondary
        case .display: return .blue
        case .audio: return .purple
        case .dpi: return .green
        case .alert: return .orange
        }
    }
}

// MARK: - Surfaces

private struct KalfaSurface: ViewModifier {
    let tint: Color?
    let isActive: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(isActive ? AnyShapeStyle((tint ?? .accentColor).opacity(0.14)) : AnyShapeStyle(.regularMaterial))
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(
                                isActive ? (tint ?? .accentColor).opacity(0.45) : .primary.opacity(0.08),
                                lineWidth: 0.5
                            )
                    }
            }
    }
}

extension View {
    func kalfaSurface(tint: Color? = nil, isActive: Bool = false, radius: CGFloat = KalfaDesign.cardRadius) -> some View {
        modifier(KalfaSurface(tint: tint, isActive: isActive, radius: radius))
    }
}

// MARK: - Tile

/// A live switch. The whole rectangle is the control, it is tinted while the
/// thing is on, and the second line always says what the current state *is*
/// rather than repeating the title.
struct KalfaTile: View {
    let title: String
    let state: String
    let symbol: String
    let role: KalfaRole
    let isOn: Bool
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: KalfaDesign.s) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? role.tint : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        (isOn ? role.tint : Color.secondary).opacity(isOn ? 0.18 : 0.10),
                        in: RoundedRectangle(cornerRadius: KalfaDesign.controlRadius, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(KalfaDesign.bodyFont.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(state)
                        .font(KalfaDesign.captionFont)
                        .foregroundStyle(isOn ? AnyShapeStyle(role.tint) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(KalfaDesign.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kalfaSurface(tint: role.tint, isActive: isOn, radius: KalfaDesign.tileRadius)
            .overlay {
                if hovering {
                    RoundedRectangle(cornerRadius: KalfaDesign.tileRadius, style: .continuous)
                        .fill(.primary.opacity(0.05))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: KalfaDesign.tileRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : KalfaDesign.motion, value: isOn)
        .accessibilityLabel(title)
        .accessibilityValue(state)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Card

/// A subject that can be opened: displays, sound, DPI, scenes.
///
/// The header is a summary line that is worth reading with the card shut — the
/// point is that the panel tells you the state of the machine before you touch
/// anything.
struct KalfaCard<Content: View>: View {
    let title: String
    let summary: String?
    let symbol: String
    let role: KalfaRole
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : KalfaDesign.motion) { isExpanded.toggle() }
            } label: {
                HStack(spacing: KalfaDesign.s) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(role.tint)
                        .frame(width: 26, height: 26)
                        .background(role.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: KalfaDesign.controlRadius, style: .continuous))

                    Text(title)
                        .font(KalfaDesign.headingFont)

                    Spacer(minLength: KalfaDesign.s)

                    if let summary {
                        Text(summary)
                            .font(KalfaDesign.captionFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(KalfaDesign.m)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(summary ?? "")
            .accessibilityHint(L10n.t(isExpanded ? "a11y.collapse" : "a11y.expand"))

            if isExpanded {
                VStack(alignment: .leading, spacing: KalfaDesign.s) {
                    Divider().opacity(0.5)
                    content()
                }
                .padding(.horizontal, KalfaDesign.m)
                .padding(.bottom, KalfaDesign.m)
                .transition(.opacity)
            }
        }
        .kalfaSurface()
        .overlay {
            if hovering && !isExpanded {
                RoundedRectangle(cornerRadius: KalfaDesign.cardRadius, style: .continuous)
                    .fill(.primary.opacity(0.04))
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering = $0 }
    }
}

// MARK: - Row

/// One setting inside a card or the tools window: a label, what it is worth now,
/// and the control that changes it.
struct KalfaRow<Control: View>: View {
    let title: String
    let value: String?
    let help: String
    @ViewBuilder let control: () -> Control

    init(
        _ title: String,
        value: String? = nil,
        help: String = "",
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.value = value
        self.help = help
        self.control = control
    }

    var body: some View {
        HStack(spacing: KalfaDesign.s) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(KalfaDesign.bodyFont)
                if let value {
                    Text(value)
                        .font(KalfaDesign.captionFont.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: KalfaDesign.s)
            control()
        }
        .frame(minHeight: 26)
        .help(help)
    }
}

/// A compact toolbar control with a visible hover and pressed state.
struct KalfaToolbarButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 27, height: 27)
                .background(
                    .primary.opacity(hovering ? 0.09 : 0.001),
                    in: RoundedRectangle(cornerRadius: KalfaDesign.controlRadius, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: KalfaDesign.controlRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The state line at the top of the panel: one chip per thing worth knowing at a
/// glance, so the machine's condition is legible before any control is touched.
struct KalfaChip: View {
    let text: String
    let symbol: String
    let tint: Color?

    init(_ text: String, symbol: String, tint: Color? = nil) {
        self.text = text
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(KalfaDesign.captionFont)
                .lineLimit(1)
        }
        .foregroundStyle(tint ?? .secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background((tint ?? .secondary).opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
