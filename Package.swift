// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpaceMaker",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "SpaceMaker", targets: ["SpaceMaker"]),
        .executable(name: "space-maker-move-helper", targets: ["SpaceMakerMoveHelper"]),
    ],
    targets: [
        .target(name: "SpaceMakerCore"),
        .executableTarget(name: "SpaceMaker", dependencies: ["SpaceMakerCore"]),
        .executableTarget(name: "SpaceMakerMoveHelper"),
    ]
)
