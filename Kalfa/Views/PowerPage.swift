import AppKit
import SwiftUI
import KalfaUI

/// When this Mac sleeps and when it does not: staying awake, presenting, and
/// the timer that ends the day.
struct PowerPage: View {

    private let caffeine = CaffeineService.shared
    private let presentation = PresentationMode.shared
    private let timer = PowerTimer.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { caffeine.isActive }, set: { _ in caffeine.toggle() })) {
                    Text(L10n.t("caffeine.now"))
                    if let value = caffeineValue { Text(value) }
                }
                .help(L10n.t("caffeine.help"))

                Picker(L10n.t("caffeine.span"), selection: Binding(get: { caffeine.span }, set: { caffeine.span = $0 })) {
                    ForEach(CaffeineService.Span.allCases) { span in
                        Text(span.minutes.map { L10n.t("caffeine.minutes", $0) } ?? L10n.t("caffeine.indefinite"))
                            .tag(span)
                    }
                }
                .pickerStyle(.segmented)
                // Fixed when the assertion is taken; changing it means taking
                // a new one.
                .disabled(caffeine.isActive)

                Toggle(L10n.t("caffeine.display"), isOn: Binding(
                    get: { caffeine.keepsDisplayAwake },
                    set: { caffeine.keepsDisplayAwake = $0 }
                ))
            } header: {
                Text(L10n.t("caffeine"))
            }

            Section {
                ForEach(caffeine.watchedApps, id: \.self) { bundleID in
                    LabeledContent(caffeine.appName(bundleID)) {
                        Button {
                            caffeine.watchedApps.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button(L10n.t("caffeine.rule.add"), systemImage: "plus") { pickApp() }
            } header: {
                Text(L10n.t("caffeine.rule"))
            } footer: {
                Text(L10n.t("caffeine.rule.help")).kalfaFootnote()
            }

            Section {
                Toggle(L10n.t("presentation.on"), isOn: Binding(
                    get: { presentation.isOn },
                    set: { _ in presentation.toggle() }
                ))
                Toggle(L10n.t("presentation.blackout"), isOn: Binding(
                    get: { presentation.blacksOutOtherScreens },
                    set: { presentation.blacksOutOtherScreens = $0 }
                ))
            } header: {
                Text(L10n.t("presentation"))
            } footer: {
                Text(L10n.t("presentation.help")).kalfaFootnote()
            }

            Section(L10n.t("timer")) {
                Picker(L10n.t("timer.ending"), selection: Binding(get: { timer.ending }, set: { timer.ending = $0 })) {
                    ForEach(PowerTimer.Ending.allCases) { ending in
                        Text(ending.label).tag(ending)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(timer.isArmed)

                Stepper(
                    L10n.t("timer.minutes", timer.minutes),
                    value: Binding(get: { timer.minutes }, set: { timer.minutes = $0 }),
                    in: 5...240,
                    step: 5
                )
                .disabled(timer.isArmed)

                LabeledContent(timerValue ?? "") {
                    if timer.isArmed {
                        Button(L10n.t("timer.cancel")) { timer.cancel() }
                    } else {
                        Button(L10n.t("timer.arm")) { timer.arm() }
                    }
                }
            }
        }
        .kalfaForm()
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier,
              !caffeine.watchedApps.contains(bundleID)
        else { return }
        caffeine.watchedApps.append(bundleID)
    }

    private var caffeineValue: String? {
        guard caffeine.isActive else { return nil }
        if caffeine.heldByRule { return L10n.t("caffeine.byRule") }
        guard let minutes = caffeine.remainingMinutes else { return L10n.t("caffeine.untilOff") }
        return L10n.t("caffeine.remaining", minutes)
    }

    private var timerValue: String? {
        guard let minutes = timer.remainingMinutes else { return nil }
        return L10n.t("timer.remaining", minutes, timer.ending.label)
    }
}
