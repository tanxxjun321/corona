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
        )
    ],
    targets: [
        .target(
            name: "CoronaCore"
        ),
        .testTarget(
            name: "CoronaCoreTests",
            dependencies: ["CoronaCore"]
        )
    ]
)
