// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// Package manifest.
let package = Package(
    name: "llfsm-bin",
    products: [
        .executable(
            name: "llfsm",
            targets: ["llfsm_bin"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.4.0"),
        .package(url: "https://github.com/CPSLabGU/LLFSMGenerate.git", from: "3.0.1"),
        .package(url: "https://github.com/CPSLabGU/VHDLModelChecker.git", from: "0.2.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "llfsm_bin",
            dependencies: [
                .target(name: "PLDCommands")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
                .unsafeFlags(["-parse-as-library"], .when(platforms: [.windows])),
            ],
        ),
        .target(
            name: "PLDCommands",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "LLFSMGenerate", package: "LLFSMGenerate"),
                .product(name: "LLFSMVerify", package: "VHDLModelChecker"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ],
        ),
        .testTarget(
            name: "llfsm_binTests",
            dependencies: [.target(name: "llfsm_bin")],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ],
        ),
    ]
)
