// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "JustSayIt",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "JustSayIt",
            path: "Sources/JustSayIt",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
