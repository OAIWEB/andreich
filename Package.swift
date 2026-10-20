// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AndreichNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AndreichNotch",
            path: "Sources/AndreichNotch",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
