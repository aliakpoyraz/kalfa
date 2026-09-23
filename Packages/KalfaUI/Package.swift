// swift-tools-version: 6.0
import PackageDescription

// The visual language and the string lookup, in one place both halves can see.
//
// They used to live in the app target, which meant the DPI module — a package —
// could not reach them and grew its own: its own tab layout instead of the
// card grammar, and its own `T("tr","en")` pairs instead of the .strings files.
// The app looked like two apps stapled together because, structurally, it was.
let package = Package(
    name: "KalfaUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KalfaUI", targets: ["KalfaUI"])
    ],
    targets: [
        .target(
            name: "KalfaUI",
            path: "Sources/KalfaUI",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
