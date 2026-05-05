// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HephaestusObservation",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HephaestusObservation", targets: ["HephaestusObservation"])
    ],
    dependencies: [
        .package(path: "../HephaestusDomain")
    ],
    targets: [
        .target(
            name: "HephaestusObservation",
            dependencies: [
                .product(name: "HephaestusDomain", package: "HephaestusDomain")
            ]
        )
    ]
)
