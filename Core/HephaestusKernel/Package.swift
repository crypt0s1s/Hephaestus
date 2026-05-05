// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HephaestusKernel",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HephaestusKernel", targets: ["HephaestusKernel"])
    ],
    targets: [
        .target(name: "HephaestusKernel")
    ]
)
