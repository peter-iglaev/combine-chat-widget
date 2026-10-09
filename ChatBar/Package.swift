// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChatBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ChatBar",
            path: "Sources/ChatBar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
