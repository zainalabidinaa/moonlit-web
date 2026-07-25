// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MoonlitCore",
    platforms: [
        .iOS(.v17),
        .macOS("14.0"),
        .tvOS(.v17),
    ],
    products: [
        .library(
            name: "MoonlitCore",
            targets: ["MoonlitCore"]
        ),
    ],
    targets: [
        .target(
            name: "MoonlitCore",
            path: "Sources/MoonlitCore"
        ),
        .testTarget(
            name: "MoonlitCoreTests",
            dependencies: ["MoonlitCore"],
            path: "Tests/MoonlitCoreTests"
        )
    ]
)
