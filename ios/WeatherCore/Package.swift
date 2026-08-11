// swift-tools-version: 5.9
import PackageDescription

// macOS is listed purely so `swift test` can run the pure-logic tests on the host
// without a simulator runtime. Nothing in WeatherCore is macOS-only.
let package = Package(
    name: "WeatherCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(name: "WeatherCore", targets: ["WeatherCore"])
    ],
    targets: [
        .target(name: "WeatherCore"),
        .testTarget(
            name: "WeatherCoreTests",
            dependencies: ["WeatherCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
