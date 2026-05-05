// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HephaestusRuntime",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HephaestusRuntime", targets: ["HephaestusRuntime"])
    ],
    dependencies: [
        .package(path: "../HephaestusDomain"),
        .package(path: "../HephaestusKernel"),
        .package(path: "../HephaestusObservation")
    ],
    targets: [
        .target(
            name: "HephaestusRuntime",
            dependencies: [
                .product(name: "HephaestusDomain", package: "HephaestusDomain"),
                .product(name: "HephaestusKernel", package: "HephaestusKernel"),
                .product(name: "HephaestusObservation", package: "HephaestusObservation")
            ]
        )
    ]
)
