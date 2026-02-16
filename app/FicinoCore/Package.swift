// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FicinoCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "FicinoCore",
            targets: ["FicinoCore"]
        )
    ],
    dependencies: [
        .package(path: "../MusicModel"),
        .package(path: "../MusicContext"),
    ],
    targets: [
        .target(
            name: "FicinoCore",
            dependencies: ["MusicModel", "MusicContext"]
        ),
    ]
)
