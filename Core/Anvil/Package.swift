// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Anvil",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "Anvil", targets: ["Anvil"])
    ],
    targets: [
        .target(name: "Anvil")
    ]
)
