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
        .executableTarget(
            name: "Wift",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources",
            sources: ["Wift"],
            resources: [
                .embedInCode("WiftLibrary/Wift.swift"),
            ]
        ),
        .testTarget(name: "WiftTests", dependencies: ["Wift"]),
    ]
)
