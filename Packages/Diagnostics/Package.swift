// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Diagnostics",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "Diagnostics", targets: ["Diagnostics"])
    ],
    targets: [
        .target(name: "Diagnostics")
    ]
)
