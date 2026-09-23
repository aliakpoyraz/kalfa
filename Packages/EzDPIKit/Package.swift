// swift-tools-version: 6.0
import PackageDescription

// The DPI half of Kalfa, kept as its own module rather than merged into the app
// target. Both halves grew up as separate menu bar apps and both define a `Log`,
// a `Diagnostics`, a `SettingsView` and an `L10n`; a module boundary settles all
// of that without renaming a single type on either side.
let package = Package(
    name: "EzDPIKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EzDPIKit", targets: ["EzDPIKit"])
    ],
    targets: [
        .target(
            name: "EzDPIKit",
            path: "Sources/EzDPIKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
