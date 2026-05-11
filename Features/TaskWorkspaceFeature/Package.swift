// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TaskWorkspaceFeature",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TaskWorkspaceFeature", targets: ["TaskWorkspaceFeature"])
    ],
    dependencies: [
        .package(path: "../../Anvil/Anvil"),
        .package(path: "../../Anvil/AnvilTheme"),
        .package(path: "../../Anvil/AnvilUI"),
        .package(path: "../../Core/HephaestusDomain"),
        .package(path: "../../Core/HephaestusKernel"),
        .package(path: "../../Core/HephaestusObservation"),
        .package(path: "../../Core/HephaestusRuntime"),
        .package(path: "../TaskWorkspaceContracts"),
    ],
    targets: [
        .target(
            name: "TaskWorkspaceFeature",
            dependencies: [
                .product(name: "Anvil", package: "Anvil"),
                .product(name: "AnvilTheme", package: "AnvilTheme"),
                .product(name: "AnvilUI", package: "AnvilUI"),
                .product(name: "HephaestusDomain", package: "HephaestusDomain"),
                .product(name: "HephaestusKernel", package: "HephaestusKernel"),
                .product(name: "HephaestusObservation", package: "HephaestusObservation"),
                .product(name: "HephaestusRuntime", package: "HephaestusRuntime"),
                .product(name: "TaskWorkspaceContracts", package: "TaskWorkspaceContracts"),
            ]
        )
    ]
)
