// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SlimPomo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Deeeep", targets: ["Deeeep"])
    ],
    targets: [
        .target(name: "SlimPomoCore"),
        .executableTarget(
            name: "Deeeep",
            dependencies: ["SlimPomoCore"],
            path: "Sources/SlimPomo"
        ),
        .testTarget(
            name: "SlimPomoCoreTests",
            dependencies: ["SlimPomoCore"]
        )
    ]
)
