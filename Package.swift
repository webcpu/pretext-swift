// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PretextSwift",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Pretext",
            targets: ["Pretext"]
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
        .executableTarget(
            name: "Demo",
            dependencies: ["Pretext", "BenchmarkSupport"],
            path: "Sources/Demo",
            resources: [
                .process("Resources"),
            ]
        ),
        .target(
            name: "BenchmarkSupport",
            dependencies: ["Pretext"],
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
