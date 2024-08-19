// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MemoryMappedCollection",
    products: [
        .library(
            name: "MemoryMappedCollection",
            targets: ["MemoryMappedCollection"]),
    ],
    targets: [
        .target(
            name: "MemoryMappedCollection"),
        .testTarget(
            name: "MemoryMappedCollectionTests",
            dependencies: ["MemoryMappedCollection"]
        ),
    ]
)
