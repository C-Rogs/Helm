// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Domain",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "PlanKit", targets: ["PlanKit"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(name: "Domain"),
        .target(
            name: "PlanKit",
            dependencies: [
                .product(name: "Core", package: "Core")
            ]
        ),
        .testTarget(
            name: "PlanKitTests",
            dependencies: ["PlanKit"]
        )
    ]
)
