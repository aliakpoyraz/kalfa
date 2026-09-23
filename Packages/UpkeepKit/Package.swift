// swift-tools-version: 6.0
import PackageDescription

// Kalfa'nın bakım yarısı: canlı ölçüm, disk analizi, temizlik ve kaldırma.
// EzDPIKit'in kurduğu emsali izler — kendi modeli, kendi güvenlik kuralları ve
// kendi arayüzü olan bir bütün, app hedefine serpiştirilmiş yirmi dosya değil.
let package = Package(
    name: "UpkeepKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UpkeepKit", targets: ["UpkeepKit"])
    ],
    targets: [
        .target(
            name: "UpkeepKit",
            path: "Sources/UpkeepKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
