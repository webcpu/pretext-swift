// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PretextSwift",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "PretextDemo",
            targets: ["PretextDemo"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "PretextDemo",
            path: "PretextDemo",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "PretextDemoTests",
            dependencies: ["PretextDemo"],
            path: "Tests/PretextDemoTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
