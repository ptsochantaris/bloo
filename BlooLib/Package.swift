// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BlooLib",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "BlooLib",
            targets: ["BlooLib"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ptsochantaris/lista", branch: "main"),
        .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.0.0"),
        .package(url: "https://github.com/alexisakers/HTMLString", from: "6.0.0")
    ],
    targets: [
        .target(
            name: "BlooLib",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "HTMLString", package: "HTMLString"),
                .product(name: "Lista", package: "lista")
            ]
        ),
        .testTarget(
            name: "BlooLibTests",
            dependencies: ["BlooLib"],
            resources: [
                .copy("Resources")
            ]
        )
    ]
)

