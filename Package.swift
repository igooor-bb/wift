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
        .package(url: "https://github.com/tuist/XcodeProj.git", from: "9.16.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.1"),
        .package(
            url: "https://github.com/ordo-one/benchmark",
            "1.34.1" ..< "1.35.0",
            traits: []
        ),
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
                .product(name: "XcodeProj", package: "XcodeProj"),
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
        .executableTarget(
            name: "WiftBenchmarks",
            dependencies: [
                .product(name: "Benchmark", package: "benchmark"),
            ],
            path: "Benchmarks/WiftBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "benchmark"),
            ]
        ),
    ]
)
