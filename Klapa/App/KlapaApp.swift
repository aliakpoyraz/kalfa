import SwiftUI

@main
struct KlapaApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var center = DisplayCenter()

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environment(center)
        } label: {
            Image(systemName: center.isClamshell ? "macbook.and.iphone" : "display")
                .accessibilityLabel("Klapa")
        }
        .menuBarExtraStyle(.window)
    }
}
