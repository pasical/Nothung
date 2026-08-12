// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NothungCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "NothungCore", targets: ["NothungCore"]),
    ],
    targets: [
        .target(name: "NothungCore"),
        .testTarget(
            name: "NothungCoreTests",
            dependencies: ["NothungCore"]
        ),
    ]
)
