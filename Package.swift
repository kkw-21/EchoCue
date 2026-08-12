// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EchoCue",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "EchoCue", targets: ["EchoCue"])
    ],
    targets: [
        .executableTarget(
            name: "EchoCue",
            path: "Sources/EchoCue",
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(
            name: "EchoCueTests",
            dependencies: ["EchoCue"],
            path: "Tests/EchoCueTests"
        )
    ]
)
