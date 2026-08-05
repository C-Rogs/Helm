// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Core",
    // macOS is only here so `swift test` has a deployment target new enough for CryptoKit.
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "Core", targets: ["Core"])
    ],
    targets: [
        .target(name: "Core"),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"]
        )
    ]
)
