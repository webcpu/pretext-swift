// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PretextSwift",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "Pretext",
            targets: ["Pretext"]
        ),
        .library(
            name: "PretextUI",
            targets: ["PretextUI"]
        ),
        .executable(
            name: "Demo",
            targets: ["Demo"]
        ),
        .executable(
            name: "Benchmark",
            targets: ["Benchmark"]
        ),
    ],
    targets: [
        .target(
            name: "Pretext",
            path: "Sources/Pretext"
        ),
        .target(
            name: "PretextUI",
            dependencies: ["Pretext"],
            path: "Sources/PretextUI"
        ),
        .executableTarget(
            name: "Demo",
            dependencies: ["Pretext", "PretextUI", "BenchmarkSupport"],
            path: "Sources/Demo",
            resources: [
                .process("Resources"),
            ]
        ),
        .target(
            name: "BenchmarkSupport",
            dependencies: ["Pretext", "PretextUI"],
            path: "Sources/Benchmark"
        ),
        .executableTarget(
            name: "Benchmark",
            dependencies: ["BenchmarkSupport"],
            path: "Sources/BenchmarkApp"
        ),
        .testTarget(
            name: "PretextTests",
            dependencies: ["Pretext"],
            path: "Tests/PretextTests"
        ),
        .testTarget(
            name: "DemoTests",
            dependencies: ["Demo", "BenchmarkSupport"],
            path: "Tests/DemoTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
