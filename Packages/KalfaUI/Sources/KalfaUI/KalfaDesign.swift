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
public enum KalfaDesign {

    public static let panelWidth: CGFloat = 392

    // Spacing scale. Four steps, used everywhere; no ad-hoc paddings.
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let edge: CGFloat = 14

    public static let tileRadius: CGFloat = 11
    public static let cardRadius: CGFloat = 13
    public static let controlRadius: CGFloat = 7

    // Type scale. Four sizes; anything else is a mistake, not a decision.
    public static let titleFont = Font.system(size: 15, weight: .semibold)
    public static let headingFont = Font.system(size: 13, weight: .semibold)
    public static let bodyFont = Font.system(size: 12)
    public static let captionFont = Font.system(size: 11)

    /// Short enough not to be in the way, long enough to be seen. Halved when the
    /// reader has asked for reduced motion.
    public static let motion = Animation.easeOut(duration: 0.18)
}

/// What a control is about.
///
/// Five roles, not eleven. Colour names the *subject* — screens are blue, sound
/// is purple, the protection half is green, something wanting attention is
/// orange, everything else is neutral. Whether a control is on is carried by the
/// tint being filled in at all, so an eleventh hue bought nothing except a panel
/// that looked like a box of highlighters.
public enum KalfaRole {
    case neutral, display, audio, dpi, alert

    public var tint: Color {
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
    public func kalfaSurface(tint: Color? = nil, isActive: Bool = false, radius: CGFloat = KalfaDesign.cardRadius) -> some View {
        modifier(KalfaSurface(tint: tint, isActive: isActive, radius: radius))
    }
}

// MARK: - Tile

/// A live switch. The whole rectangle is the control, it is tinted while the
/// thing is on, and the second line always says what the current state *is*
/// rather than repeating the title.
public struct KalfaTile: View {
    public let title: String
    public let state: String
    public let symbol: String
    public let role: KalfaRole
    public let isOn: Bool
    public let action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(title: String, state: String, symbol: String, role: KalfaRole, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.state = state
        self.symbol = symbol
        self.role = role
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
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
public struct KalfaCard<Content: View>: View {
    public let title: String
    public let summary: String?
    public let symbol: String
    public let role: KalfaRole
    @Binding public var isExpanded: Bool
    @ViewBuilder public let content: () -> Content

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        title: String,
        summary: String?,
        symbol: String,
        role: KalfaRole,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.summary = summary
        self.symbol = symbol
        self.role = role
        self._isExpanded = isExpanded
        self.content = content
    }

    public var body: some View {
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
public struct KalfaRow<Control: View>: View {
    public let title: String
    public let value: String?
    public let help: String
    @ViewBuilder public let control: () -> Control

    public init(
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

    public var body: some View {
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
public struct KalfaToolbarButton: View {
    public let systemName: String
    public let help: String
    public let action: () -> Void

    @State private var hovering = false

    public init(systemName: String, help: String, action: @escaping () -> Void) {
        self.systemName = systemName
        self.help = help
        self.action = action
    }

    public var body: some View {
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
public struct KalfaChip: View {
    public let text: String
    public let symbol: String
    public let tint: Color?

    public init(_ text: String, symbol: String, tint: Color? = nil) {
        self.text = text
        self.symbol = symbol
        self.tint = tint
    }

    public var body: some View {
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
