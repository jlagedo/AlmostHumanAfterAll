// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MusicModel",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "MusicModel",
            targets: ["MusicModel"]
        )
    ],
    targets: [
        .target(
            name: "MusicModel"
        ),
        .testTarget(
            name: "MusicModelTests",
            dependencies: ["MusicModel"]
        )
    ]
)
