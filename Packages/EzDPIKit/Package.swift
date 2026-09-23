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
    dependencies: [
        // The card grammar and the string table. Before this the DPI half had
        // its own of both, which is why it looked like a different app.
        .package(path: "../KalfaUI")
    ],
    targets: [
        .target(
            name: "EzDPIKit",
            dependencies: [.product(name: "KalfaUI", package: "KalfaUI")],
            path: "Sources/EzDPIKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The engine is ours now, so it is ours to prove. The parser and the
        // fragmenter are pure functions over bytes and are tested as such; the
        // proxy itself is tested by talking to it.
        .testTarget(
            name: "EzDPIKitTests",
            dependencies: ["EzDPIKit"],
            path: "Tests/EzDPIKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
