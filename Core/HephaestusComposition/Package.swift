// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HephaestusComposition",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HephaestusComposition", targets: ["HephaestusComposition"])
    ],
    dependencies: [
        .package(path: "../HephaestusHarness"),
        .package(path: "../HephaestusKernel"),
        .package(path: "../HephaestusLLM"),
        .package(path: "../HephaestusRuntime"),
    ],
    targets: [
        .target(
            name: "HephaestusComposition",
            dependencies: [
                .product(name: "HephaestusHarness", package: "HephaestusHarness"),
                .product(name: "HephaestusKernel", package: "HephaestusKernel"),
                .product(name: "HephaestusLLM", package: "HephaestusLLM"),
                .product(name: "HephaestusRuntime", package: "HephaestusRuntime"),
            ]
        )
    ]
)
