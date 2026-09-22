// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ENVPilot",
    platforms: [
        .macOS(.v14),
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
            // 这里刻意不声明 `resources:`：一旦声明，SwiftPM 就会生成 `Bundle.module`，
            // 它在找不到资源包时 `fatalError`，而「资源包该放哪」在不同构建工具下不一致
            // （原生 SwiftPM 去 `.app` 根找，Xcode 构建产物在 Products/ 下），1.0.0 就是
            // 因此启动即崩溃。图标由 scripts/create_dmg.sh 直接放进 `Contents/Resources/`，
            // 代码用 `Bundle.main` 读。
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
