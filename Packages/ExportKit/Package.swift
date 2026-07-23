// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ExportKit",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "ExportKit", targets: ["ExportKit"])
    ],
    targets: [
        .target(name: "ExportKit"),
        .executableTarget(
            name: "GenerateGolden",
            dependencies: ["ExportKit"],
            path: "scripts",
            sources: ["generate_golden.swift"]
        ),
        .testTarget(
            name: "ExportKitTests",
            dependencies: ["ExportKit"],
            resources: [.process("Fixtures")]
        )
    ]
)
