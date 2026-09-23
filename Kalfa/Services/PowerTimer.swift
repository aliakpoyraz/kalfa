import AppKit
import Foundation
import Observation
import KalfaUI

/// "In 45 minutes, sleep." The opposite of the keep-awake switch, and it lives
/// next to it for that reason.
@MainActor
@Observable
final class PowerTimer {

    static let shared = PowerTimer()

    enum Ending: String, CaseIterable, Identifiable {
        case sleep
        case displayOff
        case shutdown

        var id: String { rawValue }

        var label: String {
            switch self {
            case .sleep: return L10n.t("timer.sleep")
            case .displayOff: return L10n.t("timer.displayOff")
            case .shutdown: return L10n.t("timer.shutdown")
            }
        }
    }

    private(set) var firesAt: Date?
    var ending: Ending = .sleep
    var minutes = 30

    private var task: Task<Void, Never>?

    private init() {}

    var isArmed: Bool { firesAt != nil }

    var remainingMinutes: Int? {
        guard let firesAt else { return nil }
        return max(0, Int(firesAt.timeIntervalSinceNow / 60) + 1)
    }

    func arm() {
        cancel()
        let deadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        firesAt = deadline
        let ending = ending
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(self?.minutes ?? 30) * 60))
            guard !Task.isCancelled else { return }
            self?.firesAt = nil
            Self.perform(ending)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        firesAt = nil
    }

    /// Sleep and shutdown go through System Events rather than `pmset`, which
    /// wants root for both; the Apple Event asks the user once and is remembered.
    private static func perform(_ ending: Ending) {
        switch ending {
        case .sleep:
            runScript("tell application \"System Events\" to sleep")
        case .shutdown:
            runScript("tell application \"System Events\" to shut down")
        case .displayOff:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["displaysleepnow"]
            try? process.run()
        }
    }

    private static func runScript(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.display.error("power action failed: \(error.description, privacy: .public)")
        }
    }
}
