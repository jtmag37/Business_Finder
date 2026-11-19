// swift-tools-version: 5.9
import PackageDescription

// Pure-Swift game logic: no UIKit, SpriteKit or networking. Everything here is
// deterministic and unit-testable on macOS or in the iOS simulator.
let package = Package(
    name: "CitySprintCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CitySprintCore", targets: ["CitySprintCore"])
    ],
    targets: [
        .target(
            name: "CitySprintCore",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(name: "CitySprintCoreTests", dependencies: ["CitySprintCore"])
    ]
)
