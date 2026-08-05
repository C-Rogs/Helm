// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Domain",
    // macOS so `swift test` can run PlanKit/ReadinessKit/NutritionKit on the host.
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "PlanKit", targets: ["PlanKit"]),
        .library(name: "ReadinessKit", targets: ["ReadinessKit"]),
        .library(name: "NutritionKit", targets: ["NutritionKit"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(name: "Domain"),
        .target(
            name: "PlanKit",
            dependencies: [
                .product(name: "Core", package: "Core"),
                "ReadinessKit"
            ]
        ),
        .testTarget(
            name: "PlanKitTests",
            dependencies: ["PlanKit"]
        ),
        .target(
            name: "ReadinessKit",
            dependencies: [
                .product(name: "Core", package: "Core")
            ]
        ),
        .testTarget(
            name: "ReadinessKitTests",
            dependencies: ["ReadinessKit"],
            resources: [
                .copy("Fixtures")
            ]
        ),
        .target(
            name: "NutritionKit",
            dependencies: [
                .product(name: "Core", package: "Core")
            ],
            resources: [
                .copy("Resources/cofid_foods.json")
            ]
        ),
        .testTarget(
            name: "NutritionKitTests",
            dependencies: ["NutritionKit"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
