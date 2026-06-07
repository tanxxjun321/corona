// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Corona",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "CoronaCore",
            targets: ["CoronaCore"]
        ),
        .executable(
            name: "CoronaMenuBar",
            targets: ["CoronaMenuBar"]
        )
    ],
    targets: [
        .target(
            name: "CoronaCore"
        ),
        .executableTarget(
            name: "CoronaMenuBar",
            dependencies: ["CoronaCore"]
        ),
        .testTarget(
            name: "CoronaCoreTests",
            dependencies: ["CoronaCore"]
        )
    ]
)
