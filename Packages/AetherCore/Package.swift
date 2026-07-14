// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AetherCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AetherFoundation", targets: ["AetherFoundation"]),
        .library(name: "AetherServices", targets: ["AetherServices"]),
        .library(name: "AetherDesign", targets: ["AetherDesign"]),
        .library(name: "AetherUI", targets: ["AetherUI"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AetherFoundation",
            dependencies: []
        ),
        .target(
            name: "AetherServices",
            dependencies: ["AetherFoundation"]
        ),
        .target(
            name: "AetherDesign",
            dependencies: ["AetherFoundation"]
        ),
        .target(
            name: "AetherUI",
            dependencies: ["AetherDesign", "AetherFoundation"]
        ),
        .testTarget(
            name: "AetherCoreTests",
            dependencies: ["AetherFoundation", "AetherServices", "AetherDesign", "AetherUI"]
        )
    ]
)
