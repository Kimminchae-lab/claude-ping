// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeNotifier",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeNotifier",
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
