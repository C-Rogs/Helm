// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Domain",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "PlanKit", targets: ["PlanKit"]),
        .library(name: "ReadinessKit", targets: ["ReadinessKit"])
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
        )
    ]
)
