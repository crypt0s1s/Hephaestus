// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AnvilTheme",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AnvilTheme", targets: ["AnvilTheme"])
    ],
    targets: [
        .target(name: "AnvilTheme")
    ]
)
