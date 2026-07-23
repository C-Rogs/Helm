// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CoachLLM",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "CoachLLM", targets: ["CoachLLM"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Diagnostics")
    ],
    targets: [
        .target(
            name: "CoachLLM",
            dependencies: [
                "Core",
                .product(name: "Diagnostics", package: "Diagnostics", condition: .when(platforms: [.iOS]))
            ]
        ),
        .testTarget(
            name: "CoachLLMTests",
            dependencies: ["CoachLLM"],
            resources: [.process("Fixtures")]
        )
    ]
)
