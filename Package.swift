// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ENVPilot",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "ENVPilotCore",
            targets: ["ENVPilotCore"]
        ),
        .executable(
            name: "ENVPilotApp",
            targets: ["ENVPilotApp"]
        ),
        .executable(
            name: "envpilot-helper",
            targets: ["envpilot-helper"]
        ),
    ],
    targets: [
        .target(
            name: "ENVPilotCore",
            path: "Sources/NodePilotCore"
        ),
        .executableTarget(
            name: "ENVPilotApp",
            dependencies: ["ENVPilotCore"],
            path: "Sources/NodePilotApp"
        ),
        .executableTarget(
            name: "envpilot-helper",
            dependencies: ["ENVPilotCore"],
            path: "Sources/nodepilot-helper"
        ),
        .testTarget(
            name: "ENVPilotCoreTests",
            dependencies: ["ENVPilotCore"],
            path: "Tests/NodePilotCoreTests"
        ),
    ]
)
