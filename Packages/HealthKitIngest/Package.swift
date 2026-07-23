// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HealthKitIngest",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "HealthKitIngest", targets: ["HealthKitIngest"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Diagnostics"),
        .package(path: "../Domain"),
        .package(path: "../Persistence"),
        .package(path: "../CoachLLM")
    ],
    targets: [
        .target(
            name: "HealthKitIngest",
            dependencies: [
                .product(name: "Core", package: "Core"),
                .product(name: "Diagnostics", package: "Diagnostics"),
                .product(name: "ReadinessKit", package: "Domain"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "CoachLLM", package: "CoachLLM")
            ]
        ),
        .testTarget(
            name: "HealthKitIngestTests",
            dependencies: [
                "HealthKitIngest",
                .product(name: "Core", package: "Core"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "ReadinessKit", package: "Domain"),
                .product(name: "CoachLLM", package: "CoachLLM")
            ]
        )
    ]
)
