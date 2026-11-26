import AppKit
import SwiftUI
import KalfaUI

/// The shortcut list: one row per action, each row a recorder.
struct HotkeysView: View {

    private let hotkeys = HotkeyService.shared

    var body: some View {
        ForEach(HotkeyService.Action.allCases) { action in
            HotkeyRow(action: action)
        }
    }
}

private struct HotkeyRow: View {
    let action: HotkeyService.Action

    private let hotkeys = HotkeyService.shared
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: KalfaDesign.s) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t(action.titleKey))
                    .font(KalfaDesign.bodyFont)
                if let problem = hotkeys.problems[action] {
                    Text(problemText(problem))
                        .font(KalfaDesign.captionFont)
                        .foregroundStyle(KalfaTone.warn.color)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: KalfaDesign.s)

            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? L10n.t("hotkey.recording") : hotkeys.label(for: action))
                    .font(KalfaDesign.bodyFont.monospaced())
                    .frame(minWidth: 64)
                    .padding(.horizontal, KalfaDesign.s)
                    .padding(.vertical, KalfaDesign.xs)
                    .background(
                        isRecording ? AnyShapeStyle(Color.accentColor.opacity(0.22)) : AnyShapeStyle(KalfaDesign.wash),
                        in: RoundedRectangle(cornerRadius: KalfaDesign.controlRadius, style: .continuous)
                    )
                    .overlay {
                        if isRecording {
                            RoundedRectangle(cornerRadius: KalfaDesign.controlRadius, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 1)
                        }
                    }
            }
            .buttonStyle(.plain)
            .help(L10n.t("hotkey.record.help"))

            Button {
                stopRecording()
                hotkeys.setBinding(nil, for: action)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(L10n.t("hotkey.disable"))
            .disabled(hotkeys.binding(for: action) == nil)

            Button {
                stopRecording()
                hotkeys.resetBinding(for: action)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(L10n.t("hotkey.reset"))
            .disabled(hotkeys.isDefault(action))
        }
        .onDisappear(perform: stopRecording)
    }

    private func problemText(_ problem: HotkeyService.Problem) -> String {
        switch problem {
        case .taken:
            return L10n.t("hotkey.problem.taken")
        case .duplicate(let other):
            return L10n.t("hotkey.problem.duplicate", L10n.t(other.titleKey))
        }
    }

    /// A local monitor is enough: the panel is key while it is open, so the
    /// keystroke is ours to swallow. Returning nil keeps it from also reaching
    /// the text field behind the popover.
    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 {  // Escape cancels rather than binding.
                stopRecording()
                return nil
            }
            if let binding = HotkeyService.Binding(event: event) {
                hotkeys.setBinding(binding, for: action)
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
