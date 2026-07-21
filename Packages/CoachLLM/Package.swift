// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CoachLLM",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "CoachLLM", targets: ["CoachLLM"])
    ],
    targets: [
        .target(name: "CoachLLM")
    ]
)
