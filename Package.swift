// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpaceMaker",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "SpaceMaker", targets: ["SpaceMaker"]),
        .executable(name: "space-maker-move-helper", targets: ["SpaceMakerMoveHelper"]),
        .executable(name: "space-maker-mcp", targets: ["SpaceMakerMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.9.0"),
    ],
    targets: [
        .target(name: "SpaceMakerCore"),
        .executableTarget(name: "SpaceMaker", dependencies: ["SpaceMakerCore"]),
        .executableTarget(name: "SpaceMakerMoveHelper"),
        .executableTarget(
            name: "SpaceMakerMCP",
            dependencies: ["SpaceMakerCore", .product(name: "MCP", package: "swift-sdk")]
        ),
        .testTarget(name: "SpaceMakerCoreTests", dependencies: ["SpaceMakerCore"]),
    ]
)
