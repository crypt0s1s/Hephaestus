// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HephaestusLLM",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HephaestusLLM", targets: ["HephaestusLLM"])
    ],
    dependencies: [
        .package(path: "../HephaestusKernel")
    ],
    targets: [
        .target(
            name: "HephaestusLLM",
            dependencies: [
                .product(name: "HephaestusKernel", package: "HephaestusKernel")
            ]
        )
    ]
)
