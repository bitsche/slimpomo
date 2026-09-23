// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SlimPomo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SlimPomo", targets: ["SlimPomo"])
    ],
    targets: [
        .target(name: "SlimPomoCore"),
        .executableTarget(
            name: "SlimPomo",
            dependencies: ["SlimPomoCore"]
        ),
        .testTarget(
            name: "SlimPomoCoreTests",
            dependencies: ["SlimPomoCore"]
        )
    ]
)
