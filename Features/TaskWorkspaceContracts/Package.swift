// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TaskWorkspaceContracts",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TaskWorkspaceContracts", targets: ["TaskWorkspaceContracts"])
    ],
    dependencies: [
        .package(path: "../../Anvil/Anvil")
    ],
    targets: [
        .target(
            name: "TaskWorkspaceContracts",
            dependencies: [
                .product(name: "Anvil", package: "Anvil")
            ]
        )
    ]
)
