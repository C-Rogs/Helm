// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"])
    ],
    dependencies: [
        .package(path: "../Diagnostics")
    ],
    targets: [
        .target(
            name: "DesignSystem",
            dependencies: ["Diagnostics"],
            resources: [
                .process("Resources/Fonts"),
                .process("Resources/Haptics")
            ]
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"]
        )
    ]
)
