// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AnvilUI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AnvilUI", targets: ["AnvilUI"])
    ],
    dependencies: [
        .package(path: "../AnvilTheme")
    ],
    targets: [
        .target(
            name: "AnvilUI",
            dependencies: [
                .product(name: "AnvilTheme", package: "AnvilTheme")
            ]
        )
    ]
)
