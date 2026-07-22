// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HealthKitIngest",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "HealthKitIngest", targets: ["HealthKitIngest"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Diagnostics"),
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "HealthKitIngest",
            dependencies: [
                .product(name: "Core", package: "Core"),
                .product(name: "Diagnostics", package: "Diagnostics"),
                .product(name: "Persistence", package: "Persistence")
            ]
        ),
        .testTarget(
            name: "HealthKitIngestTests",
            dependencies: [
                "HealthKitIngest",
                .product(name: "Core", package: "Core"),
                .product(name: "Persistence", package: "Persistence")
            ]
        )
    ]
)
