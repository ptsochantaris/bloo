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
        .package(url: "https://github.com/ptsochantaris/lista", branch: "main")
    ],
    targets: [
        .target(
            name: "BlooLib",
            dependencies: [
                .product(name: "Lista", package: "lista")
            ]
        ),
        .testTarget(
            name: "BlooLibTests",
            dependencies: ["BlooLib"]
        )
    ]
)
