// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CoreArchitecturePOC",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "Anvil", targets: ["Anvil"]),
        .library(name: "HephaestusKernel", targets: ["HephaestusKernel"]),
        .library(name: "HephaestusLLM", targets: ["HephaestusLLM"]),
        .library(name: "ChatContracts", targets: ["ChatContracts"]),
        .library(name: "ChatFeature", targets: ["ChatFeature"]),
        .library(name: "LinkProbeFeature", targets: ["LinkProbeFeature"])
    ],
    targets: [
        .target(name: "Anvil"),
        .target(name: "HephaestusKernel"),
        .target(
            name: "HephaestusLLM",
            dependencies: ["HephaestusKernel"]
        ),
        .target(
            name: "ChatContracts",
            dependencies: ["Anvil"]
        ),
        .target(
            name: "ChatFeature",
            dependencies: ["Anvil", "ChatContracts", "HephaestusKernel"]
        ),
        .target(
            name: "LinkProbeFeature",
            dependencies: ["Anvil", "ChatContracts"]
        ),
        .testTarget(
            name: "CoreArchitecturePOCTests",
            dependencies: [
                "Anvil",
                "HephaestusKernel",
                "HephaestusLLM",
                "ChatContracts",
                "ChatFeature",
                "LinkProbeFeature"
            ]
        )
    ]
)
