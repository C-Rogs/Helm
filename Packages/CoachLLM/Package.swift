// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CoachLLM",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "CoachLLM", targets: ["CoachLLM"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "CoachLLM",
            dependencies: ["Core"]
        ),
        .testTarget(
            name: "CoachLLMTests",
            dependencies: ["CoachLLM"],
            resources: [.process("Fixtures")]
        )
    ]
)
