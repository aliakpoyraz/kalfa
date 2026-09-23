import AppKit

/// Uygulama açılıp kapanmasını NSWorkspace bildirimleriyle izler.
/// Eski kabuk betiği 5 saniyede bir pgrep yapıyordu; burada gecikme yok.
@MainActor
final class AppWatcher {
    private(set) var runningBundleIDs: Set<String> = []
    private var onChange: () -> Void = {}

    func start(onChange: @escaping () -> Void) {
        self.onChange = onChange
        refresh()

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                           object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier else { return }
            MainActor.assumeIsolated {
                self?.runningBundleIDs.insert(id)
                self?.onChange()
            }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                           object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier else { return }
            MainActor.assumeIsolated {
                self?.runningBundleIDs.remove(id)
                self?.onChange()
            }
        }
    }

    func refresh() {
        runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
    }

    func isRunning(_ bundleID: String) -> Bool {
        runningBundleIDs.contains(bundleID)
    }
}
