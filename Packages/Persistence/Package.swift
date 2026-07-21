// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Persistence",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "Persistence", targets: ["Persistence"])
    ],
    targets: [
        .target(name: "Persistence")
    ]
)
