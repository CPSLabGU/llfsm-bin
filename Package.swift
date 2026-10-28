// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// Package manifest.
let package = Package(
    name: "llfsm-bin",
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "llfsm_bin",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ],
        ),
        .testTarget(
            name: "llfsm_binTests",
            dependencies: ["llfsm_bin"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ],
        ),
    ]
)
