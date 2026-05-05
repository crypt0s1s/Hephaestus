// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HephaestusDomain",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HephaestusDomain", targets: ["HephaestusDomain"])
    ],
    targets: [
        .target(name: "HephaestusDomain")
    ]
)
