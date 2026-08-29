// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "wift",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "wift", targets: ["Wift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.1"),
    ],
    targets: [
        .target(
            name: "WiftLibrary",
            path: "Sources/WiftLibrary"
        ),
        .executableTarget(
            name: "Wift",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Wift",
            plugins: [
                "EmbedWiftLibraryPlugin",
            ]
        ),
        .executableTarget(
            name: "EmbedWiftLibraryTool",
            path: "Plugins/EmbedWiftLibraryTool"
        ),
        .plugin(
            name: "EmbedWiftLibraryPlugin",
            capability: .buildTool(),
            dependencies: ["EmbedWiftLibraryTool"],
            path: "Plugins/EmbedWiftLibraryPlugin"
        ),
        .testTarget(name: "WiftTests", dependencies: ["Wift"]),
        .testTarget(name: "WiftLibraryTests", dependencies: ["WiftLibrary"]),
    ]
)
