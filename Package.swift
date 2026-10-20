// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dorothy",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.9.0"),
    ],
    targets: [
        .target(name: "DorothyCore"),
        .executableTarget(name: "Dorothy", dependencies: ["DorothyCore"]),
        .executableTarget(name: "dorothy-mcp", dependencies: [
            "DorothyCore",
            .product(name: "MCP", package: "swift-sdk"),
        ]),
        .testTarget(name: "DorothyCoreTests", dependencies: ["DorothyCore"]),
    ],
    swiftLanguageModes: [.v5]
)
