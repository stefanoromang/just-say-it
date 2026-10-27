// swift-tools-version:6.0
// Just Say It – created by Stefano Roman Gunness · MIT License
import PackageDescription

let package = Package(
    name: "JustSayIt",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "JustSayIt",
            path: "Sources/JustSayIt",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Self-checking tests for the text rules: `swift run RuleTests`
        .executableTarget(
            name: "RuleTests",
            path: "Tests",
            sources: ["RuleTests/main.swift", "Shared"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
