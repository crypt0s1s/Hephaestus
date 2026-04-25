// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HephaestusWorkspace",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "Anvil", targets: ["Anvil"]),
        .library(name: "HephaestusKernel", targets: ["HephaestusKernel"]),
        .library(name: "HephaestusLLM", targets: ["HephaestusLLM"]),
        .library(name: "HephaestusRuntime", targets: ["HephaestusRuntime"]),
        .library(name: "HephaestusComposition", targets: ["HephaestusComposition"]),
        .library(name: "ChatContracts", targets: ["ChatContracts"]),
        .library(name: "ChatFeature", targets: ["ChatFeature"]),
        .executable(name: "HephaestusCLI", targets: ["HephaestusCLI"])
    ],
    targets: [
        .target(
            name: "Anvil",
            path: "Core/Anvil/Sources/Anvil"
        ),
        .target(
            name: "HephaestusKernel",
            path: "Core/HephaestusKernel/Sources/HephaestusKernel"
        ),
        .target(
            name: "HephaestusLLM",
            dependencies: ["HephaestusKernel"],
            path: "Core/HephaestusLLM/Sources/HephaestusLLM"
        ),
        .target(
            name: "HephaestusRuntime",
            dependencies: ["HephaestusKernel"],
            path: "Core/HephaestusRuntime/Sources/HephaestusRuntime"
        ),
        .target(
            name: "HephaestusComposition",
            dependencies: ["HephaestusKernel", "HephaestusLLM", "HephaestusRuntime"],
            path: "Core/HephaestusComposition/Sources/HephaestusComposition"
        ),
        .target(
            name: "ChatContracts",
            dependencies: ["Anvil"],
            path: "Features/ChatContracts/Sources/ChatContracts"
        ),
        .target(
            name: "ChatFeature",
            dependencies: ["Anvil", "ChatContracts", "HephaestusRuntime"],
            path: "Features/ChatFeature/Sources/ChatFeature"
        ),
        .executableTarget(
            name: "HephaestusCLI",
            dependencies: ["HephaestusComposition", "HephaestusRuntime"],
            path: "Apps/HephaestusCLI/Sources/HephaestusCLI"
        ),
        .testTarget(
            name: "HephaestusRuntimeTests",
            dependencies: [
                "Anvil",
                "ChatFeature",
                "HephaestusComposition",
                "HephaestusLLM",
                "HephaestusRuntime"
            ],
            path: "Tests/HephaestusRuntimeTests"
        )
    ]
)
