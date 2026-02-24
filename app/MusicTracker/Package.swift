// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MusicTracker",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "MusicTracker",
            targets: ["MusicTracker"]
        )
    ],
    targets: [
        .target(
            name: "MusicTracker"
        ),
    ]
)
