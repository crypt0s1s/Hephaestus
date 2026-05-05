// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HephaestusWorkspace",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "Anvil", targets: ["Anvil"]),
        .library(name: "AnvilTheme", targets: ["AnvilTheme"]),
        .library(name: "AnvilUI", targets: ["AnvilUI"]),
        .library(name: "HephaestusDomain", targets: ["HephaestusDomain"]),
        .library(name: "HephaestusObservation", targets: ["HephaestusObservation"]),
        .library(name: "HephaestusHarness", targets: ["HephaestusHarness"]),
        .library(name: "HephaestusKernel", targets: ["HephaestusKernel"]),
        .library(name: "HephaestusTools", targets: ["HephaestusTools"]),
        .library(name: "HephaestusLLM", targets: ["HephaestusLLM"]),
        .library(name: "HephaestusRuntime", targets: ["HephaestusRuntime"]),
        .library(name: "HephaestusComposition", targets: ["HephaestusComposition"]),
        .library(name: "TaskWorkspaceContracts", targets: ["TaskWorkspaceContracts"]),
        .library(name: "TaskWorkspaceFeature", targets: ["TaskWorkspaceFeature"]),
        .executable(name: "HephaestusCLI", targets: ["HephaestusCLI"])
    ],
    targets: [
        .target(
            name: "Anvil",
            path: "Anvil/Anvil/Sources/Anvil"
        ),
        .target(
            name: "AnvilTheme",
            path: "Anvil/AnvilTheme/Sources/AnvilTheme"
        ),
        .target(
            name: "AnvilUI",
            dependencies: ["AnvilTheme"],
            path: "Anvil/AnvilUI/Sources/AnvilUI"
        ),
        .target(
            name: "HephaestusDomain",
            path: "Core/HephaestusDomain/Sources/HephaestusDomain"
        ),
        .target(
            name: "HephaestusObservation",
            dependencies: ["HephaestusDomain"],
            path: "Core/HephaestusObservation/Sources/HephaestusObservation"
        ),
        .target(
            name: "HephaestusHarness",
            dependencies: ["HephaestusDomain", "HephaestusObservation"],
            path: "Core/HephaestusHarness/Sources/HephaestusHarness"
        ),
        .target(
            name: "HephaestusKernel",
            path: "Core/HephaestusKernel/Sources/HephaestusKernel"
        ),
        .target(
            name: "HephaestusTools",
            dependencies: ["HephaestusKernel"],
            path: "Core/HephaestusTools/Sources/HephaestusTools"
        ),
        .target(
            name: "HephaestusLLM",
            dependencies: ["HephaestusKernel"],
            path: "Core/HephaestusLLM/Sources/HephaestusLLM"
        ),
        .target(
            name: "HephaestusRuntime",
            dependencies: ["HephaestusDomain", "HephaestusKernel", "HephaestusObservation"],
            path: "Core/HephaestusRuntime/Sources/HephaestusRuntime"
        ),
        .target(
            name: "HephaestusComposition",
            dependencies: ["HephaestusHarness", "HephaestusKernel", "HephaestusLLM", "HephaestusRuntime"],
            path: "Core/HephaestusComposition/Sources/HephaestusComposition"
        ),
        .target(
            name: "TaskWorkspaceContracts",
            dependencies: ["Anvil"],
            path: "Features/TaskWorkspaceContracts/Sources/TaskWorkspaceContracts"
        ),
        .target(
            name: "TaskWorkspaceFeature",
            dependencies: ["Anvil", "AnvilTheme", "AnvilUI", "TaskWorkspaceContracts", "HephaestusDomain", "HephaestusKernel", "HephaestusObservation", "HephaestusRuntime"],
            path: "Features/TaskWorkspaceFeature/Sources/TaskWorkspaceFeature"
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
                "AnvilTheme",
                "AnvilUI",
                "HephaestusComposition",
                "HephaestusDomain",
                "HephaestusHarness",
                "HephaestusLLM",
                "HephaestusObservation",
                "HephaestusRuntime",
                "HephaestusTools",
                "TaskWorkspaceFeature",
                "TaskWorkspaceContracts"
            ],
            path: "Tests/HephaestusRuntimeTests"
        )
    ]
)
