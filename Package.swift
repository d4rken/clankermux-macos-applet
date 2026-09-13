// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ClankermuxUsage",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ClankermuxCore"),
        .executableTarget(
            name: "ClankermuxUsage",
            dependencies: ["ClankermuxCore"]
        ),
        .testTarget(
            name: "ClankermuxCoreTests",
            dependencies: ["ClankermuxCore"],
            resources: [.copy("Examples")]
        ),
        .testTarget(
            name: "ClankermuxUsageTests",
            dependencies: ["ClankermuxUsage"]
        ),
    ]
)
