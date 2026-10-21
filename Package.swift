// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dorothy",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.9.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "DorothyCore"),
        .executableTarget(name: "Dorothy", dependencies: [
            "DorothyCore",
            .product(name: "Sparkle", package: "Sparkle"),
        ]),
        .executableTarget(name: "dorothy-mcp", dependencies: [
            "DorothyCore",
            .product(name: "MCP", package: "swift-sdk"),
        ]),
        .testTarget(name: "DorothyCoreTests", dependencies: ["DorothyCore"]),
    ],
    swiftLanguageModes: [.v5]
)
