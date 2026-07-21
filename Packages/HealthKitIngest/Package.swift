// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HealthKitIngest",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "HealthKitIngest", targets: ["HealthKitIngest"])
    ],
    targets: [
        .target(name: "HealthKitIngest")
    ]
)
