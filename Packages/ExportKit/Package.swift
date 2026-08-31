// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ExportKit",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "ExportKit", targets: ["ExportKit"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "ExportKit",
            dependencies: [
                .product(name: "Core", package: "Core")
            ]
        ),
        .testTarget(
            name: "ExportKitTests",
            dependencies: ["ExportKit"],
            resources: [.process("Fixtures")]
        )
    ]
)
