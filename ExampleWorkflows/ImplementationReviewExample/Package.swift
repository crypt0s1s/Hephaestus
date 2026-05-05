// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ImplementationReviewExample",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ImplementationReviewWorkflow", targets: ["ImplementationReviewWorkflow"])
    ],
    targets: [
        .executableTarget(name: "ImplementationReviewWorkflow")
    ]
)
