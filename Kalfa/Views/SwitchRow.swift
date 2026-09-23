import SwiftUI

/// One labelled switch with the value it controls shown next to it.
///
/// Every capability in Kalfa that is genuinely binary is presented this way, so
/// the panel reads as a list of things that are on or off rather than a set of
/// menus to go digging through.
struct SwitchRow<Trailing: View>: View {

    let title: String
    /// What the switch is currently worth, e.g. `5120 × 2880 px` or `180 Hz`.
    let value: String?
    let isOn: Binding<Bool>
    let isEnabled: Bool
    let help: String
    @ViewBuilder let trailing: Trailing

    init(
        _ title: String,
        value: String? = nil,
        isOn: Binding<Bool>,
        isEnabled: Bool = true,
        help: String = "",
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.value = value
        self.isOn = isOn
        self.isEnabled = isEnabled
        self.help = help
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                if let value {
                    Text(value)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            trailing

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!isEnabled)
        }
        .opacity(isEnabled ? 1 : 0.45)
        .help(help)
    }
}
