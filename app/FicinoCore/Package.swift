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
        .package(path: "../MusicTracker"),
    ],
    targets: [
        .target(
            name: "FicinoCore",
            // MusicTracker is re-exported so the app target can link it transitively.
            // FicinoCore itself doesn't use MusicTracker — the Ficino app target does.
            dependencies: ["MusicModel", "MusicContext", "MusicTracker"]
        ),
    ]
)
