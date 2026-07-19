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
        .library(name: "AetherUI", targets: ["AetherUI"]),
        // Task 24: AetherSDK 顶层入口，依赖 AetherServices / AetherFoundation / AetherRust
        .library(name: "AetherSDK", targets: ["AetherSDK"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AetherFoundation",
            dependencies: []
        ),
        .binaryTarget(name: "AetherRustBin", path: "aether_core.xcframework"),
        .target(
            name: "AetherRust",
            dependencies: ["AetherRustBin"],
            path: "Sources/AetherRust",
            publicHeadersPath: "include"
        ),
        .target(
            name: "AetherServices",
            dependencies: ["AetherFoundation", "AetherRust"]
        ),
        .target(
            name: "AetherDesign",
            dependencies: ["AetherFoundation"]
        ),
        .target(
            name: "AetherUI",
            dependencies: ["AetherDesign", "AetherFoundation"]
        ),
        // Task 24 阶段 1: AetherSDK target，作为第三方集成的统一入口
        .target(
            name: "AetherSDK",
            dependencies: ["AetherFoundation", "AetherServices", "AetherRust"],
            path: "Sources/AetherSDK"
        ),
        .testTarget(
            name: "AetherCoreTests",
            dependencies: ["AetherFoundation", "AetherServices", "AetherDesign", "AetherUI"]
        ),
        // Task 24 阶段 1: AetherSDK 单元测试
        .testTarget(
            name: "AetherSDKTests",
            dependencies: ["AetherSDK", "AetherFoundation", "AetherServices"],
            path: "Tests/AetherSDKTests"
        )
    ]
)
