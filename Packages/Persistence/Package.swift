// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Persistence",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "Persistence", targets: ["Persistence"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../CoachLLM"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.3")
    ],
    targets: [
        .target(
            name: "Persistence",
            dependencies: [
                "Core",
                "CoachLLM",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            resources: [
                .copy("Resources/ExerciseSeed")
            ]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", "Core"],
            resources: [.process("Fixtures")]
        )
    ]
)
