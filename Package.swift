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
                .enableUpcomingFeature("ApproachableConcurrency")
            ],
        ),
        .target(
            name: "PLDCommands",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "CommandUtils"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ],
        ),
        .target(
            name: "CommandUtils",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "ProcessTree"),
            ]
        ),
        .target(
            name: "ProcessTree",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "llfsm_binTests",
            dependencies: [.target(name: "llfsm_bin"), .target(name: "CommandUtils")],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ],
        ),
        .testTarget(
            name: "CommandUtilsTests",
            dependencies: [.target(name: "CommandUtils"), .target(name: "ProcessTree")]
        ),
    ]
)
