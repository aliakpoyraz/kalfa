import SwiftUI

/// Kalfa's visual language.
///
/// Four rules:
///
/// 1. **The panel is a remote, the window is settings.** What gets touched
///    several times a day sits in the panel as a slider or a switch; what gets
///    set once lives in the window as a form. Nothing has a copy in both.
/// 2. **Colour says state, not subject.** Something that is on fills with the
///    system accent. Orange is a warning, red is an error or a muted microphone,
///    and that is the whole palette. Icons are monochrome.
/// 3. **One scale.** Five spacings and five type sizes; a literal number in a
///    view is a mistake, not a decision.
/// 4. **One control per kind of choice.** On/off is a switch everywhere, two to
///    four options are a segmented control, more are a menu.
public enum KalfaDesign {

    public static let panelWidth: CGFloat = 340

    // Spacing.
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24

    public static let controlRadius: CGFloat = 8
    public static let groupRadius: CGFloat = 10

    /// The height of a slider track and the diameter of its knob.
    public static let sliderHeight: CGFloat = 22
    /// The round face of a quick toggle.
    public static let toggleSize: CGFloat = 38
    /// Forms stop growing here, so a label and its control stay within reach of
    /// each other however wide the window is dragged.
    public static let formWidth: CGFloat = 600
    /// Left edge of a window page, matching where a grouped form puts its rows.
    public static let pageInset: CGFloat = 20

    // Type.
    public static let captionFont = Font.system(size: 11)
    public static let bodyFont = Font.system(size: 13)
    public static let headingFont = Font.system(size: 13, weight: .semibold)
    public static let titleFont = Font.system(size: 15, weight: .semibold)
    public static let pageFont = Font.system(size: 20, weight: .semibold)

    /// Short enough not to be in the way, long enough to be seen.
    public static let motion = Animation.easeOut(duration: 0.18)

    /// The quiet fill behind controls and groups. A wash of the text colour, not
    /// a material: a material samples the desktop behind the window, and a
    /// control must not change colour with the wallpaper.
    public static let wash = Color.primary.opacity(0.07)
}

/// What a colour is allowed to mean.
public enum KalfaTone {
    case accent, ok, warn, bad, neutral

    public var color: Color {
        switch self {
        case .accent: return .accentColor
        case .ok: return .green
        case .warn: return .orange
        case .bad: return .red
        case .neutral: return .secondary
        }
    }
}

// MARK: - Slider

/// The panel's slider: a wide track you can hit without aiming, with the value
/// read out beside it.
///
/// `zero` marks where a second, different kind of range begins below the first —
/// brightness uses it for the stretch where the backlight has run out and the
/// picture is darkened instead. That stretch is drawn hatched so the change of
/// meaning is visible before the knob gets there, and the knob catches briefly
/// at the boundary.
public struct KalfaSlider: View {

    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let zero: Double?
    private let symbol: String
    private let label: String
    private let valueText: String
    private let isEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme

    public init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        zero: Double? = nil,
        symbol: String,
        label: String,
        valueText: String,
        isEnabled: Bool = true
    ) {
        self._value = value
        self.range = range
        self.zero = zero
        self.symbol = symbol
        self.label = label
        self.valueText = valueText
        self.isEnabled = isEnabled
    }

    public var body: some View {
        HStack(spacing: KalfaDesign.s) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            track

            Text(valueText)
                .font(KalfaDesign.captionFont.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private var track: some View {
        GeometryReader { geometry in
            let knob = KalfaDesign.sliderHeight
            let travel = max(geometry.size.width - knob, 1)
            let position = knob / 2 + travel * fraction(of: value)
            let boundary = zeroFraction.map { knob / 2 + travel * $0 }
            let isBelow = zero.map { value < $0 } ?? false

            ZStack(alignment: .leading) {
                Capsule().fill(KalfaDesign.wash)

                Capsule()
                    .fill(isBelow ? AnyShapeStyle(Color.secondary.opacity(0.55)) : AnyShapeStyle(fill))
                    .frame(width: position + knob / 2)

                if let boundary {
                    Hatch()
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.35 : 0.22), lineWidth: 1)
                        .frame(width: boundary)
                        .clipShape(Capsule().size(width: geometry.size.width, height: knob))
                    Rectangle()
                        .fill(Color.primary.opacity(0.5))
                        .frame(width: 1.5, height: knob * 0.45)
                        .offset(x: boundary - 0.75)
                }

                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                    .frame(width: knob, height: knob)
                    .offset(x: position - knob / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let raw = (drag.location.x - knob / 2) / travel
                        value = snapped(range.lowerBound + min(max(raw, 0), 1) * (range.upperBound - range.lowerBound))
                    }
            )
        }
        .frame(height: KalfaDesign.sliderHeight)
    }

    private var fill: Color {
        colorScheme == .dark ? .white.opacity(0.85) : .white
    }

    private func fraction(of value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private var zeroFraction: Double? {
        guard let zero, zero > range.lowerBound else { return nil }
        return fraction(of: zero)
    }

    /// Whole numbers only, and a small catch at the boundary so "exactly the
    /// lowest backlight" is easy to land on from either side.
    private func snapped(_ raw: Double) -> Double {
        let rounded = raw.rounded()
        if let zero, zero > range.lowerBound, abs(rounded - zero) <= 2 { return zero }
        return rounded
    }
}

/// Diagonal lines across whatever rectangle it is given.
private struct Hatch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let gap: CGFloat = 5
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += gap
        }
        return path
    }
}

// MARK: - Quick toggle

/// A round switch with its name underneath: the things that get flicked on the
/// way past. Filled means on.
///
/// A toggle with more than two states takes a `menu`. The click still just turns
/// the thing on or off — it never cycles through modes blind — and the modes
/// are a right-click away.
public struct KalfaQuickToggle<MenuContent: View>: View {

    private let title: String
    private let symbol: String
    private let isOn: Bool
    private let tone: KalfaTone
    private let help: String
    private let action: () -> Void
    private let menu: MenuContent

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ title: String,
        symbol: String,
        isOn: Bool,
        tone: KalfaTone = .accent,
        help: String = "",
        action: @escaping () -> Void,
        @ViewBuilder menu: () -> MenuContent
    ) {
        self.title = title
        self.symbol = symbol
        self.isOn = isOn
        self.tone = tone
        self.help = help
        self.action = action
        self.menu = menu()
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: KalfaDesign.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isOn ? Color.white : Color.primary)
                    .frame(width: KalfaDesign.toggleSize, height: KalfaDesign.toggleSize)
                    .background(
                        isOn ? AnyShapeStyle(tone.color) : AnyShapeStyle(Color.primary.opacity(hovering ? 0.13 : 0.07)),
                        in: Circle()
                    )

                Text(title)
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : KalfaDesign.motion, value: isOn)
        .contextMenu { menu }
        .help(help)
        .accessibilityLabel(title)
        .accessibilityValue(help)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

extension KalfaQuickToggle where MenuContent == EmptyView {
    public init(
        _ title: String,
        symbol: String,
        isOn: Bool,
        tone: KalfaTone = .accent,
        help: String = "",
        action: @escaping () -> Void
    ) {
        self.init(title, symbol: symbol, isOn: isOn, tone: tone, help: help, action: action) { EmptyView() }
    }
}

// MARK: - Group and rows

extension View {
    /// The rounded wash that holds a set of rows in the panel.
    public func kalfaGroup() -> some View {
        background(KalfaDesign.wash, in: RoundedRectangle(cornerRadius: KalfaDesign.groupRadius, style: .continuous))
    }

    /// Inner padding of one row inside a group.
    public func kalfaRowPadding() -> some View {
        padding(.horizontal, KalfaDesign.m).padding(.vertical, KalfaDesign.s)
    }
}

/// The line between two rows of a group.
public struct KalfaDivider: View {
    public init() {}
    public var body: some View {
        Divider().padding(.leading, KalfaDesign.m)
    }
}

/// A row that goes somewhere: a subject on the left, what it is worth right now
/// on the right, and a chevron.
public struct KalfaNavRow: View {

    private let title: String
    private let value: String
    private let action: () -> Void

    @State private var hovering = false

    public init(_ title: String, value: String, action: @escaping () -> Void) {
        self.title = title
        self.value = value
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: KalfaDesign.s) {
                Text(title)
                    .font(KalfaDesign.headingFont)
                Spacer(minLength: KalfaDesign.s)
                Text(value)
                    .font(KalfaDesign.captionFont.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .kalfaRowPadding()
            .background(Color.primary.opacity(hovering ? 0.05 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

/// One setting: its name, an optional line saying what it is worth, and the
/// control that changes it. Used wherever a native form is not available — the
/// panel's inner pages and the display cards.
public struct KalfaSettingRow<Accessory: View, Control: View>: View {

    private let title: String
    private let detail: String?
    private let help: String
    private let accessory: Accessory
    private let control: Control

    public init(
        _ title: String,
        detail: String? = nil,
        help: String = "",
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.help = help
        self.accessory = accessory()
        self.control = control()
    }

    public var body: some View {
        HStack(spacing: KalfaDesign.s) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(KalfaDesign.bodyFont)
                if let detail {
                    Text(detail)
                        .font(KalfaDesign.captionFont.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            accessory
            Spacer(minLength: KalfaDesign.s)
            control
        }
        .frame(minHeight: 28)
        .help(help)
    }
}

extension KalfaSettingRow where Accessory == EmptyView {
    public init(
        _ title: String,
        detail: String? = nil,
        help: String = "",
        @ViewBuilder control: () -> Control
    ) {
        self.init(title, detail: detail, help: help, accessory: { EmptyView() }, control: control)
    }
}

/// A switch the size the panel wants, with no label of its own.
public struct KalfaSwitch: View {
    private let isOn: Binding<Bool>
    private let isEnabled: Bool

    public init(_ isOn: Binding<Bool>, isEnabled: Bool = true) {
        self.isOn = isOn
        self.isEnabled = isEnabled
    }

    public var body: some View {
        Toggle("", isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!isEnabled)
    }
}

// MARK: - Badge

/// A short word that qualifies the thing next to it, in the tone of what it
/// means.
public struct KalfaBadge: View {

    private let text: String
    private let symbol: String?
    private let tone: KalfaTone

    public init(_ text: String, symbol: String? = nil, tone: KalfaTone = .neutral) {
        self.text = text
        self.symbol = symbol
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(KalfaDesign.captionFont.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(tone.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tone.color.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Icon button

/// A small borderless button that is only an icon, with a visible hover.
public struct KalfaIconButton: View {

    private let systemName: String
    private let help: String
    private let action: () -> Void

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
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(
                    Color.primary.opacity(hovering ? 0.09 : 0.001),
                    in: RoundedRectangle(cornerRadius: KalfaDesign.controlRadius, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
