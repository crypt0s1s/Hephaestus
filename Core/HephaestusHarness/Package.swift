// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HephaestusHarness",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HephaestusHarness", targets: ["HephaestusHarness"])
    ],
    dependencies: [
        .package(path: "../HephaestusDomain"),
        .package(path: "../HephaestusObservation"),
    ],
    targets: [
        .target(
            name: "HephaestusHarness",
            dependencies: [
                .product(name: "HephaestusDomain", package: "HephaestusDomain"),
                .product(name: "HephaestusObservation", package: "HephaestusObservation"),
            ]
        )
    ]
)
