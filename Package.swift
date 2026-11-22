// swift-tools-version:5.9
// File-format models that IDE Studio and its Splunk add-on both use: Splunk .conf files, JSON that
// keeps its key order, Simple XML and Dashboard Studio dashboards, and app navigation.
import PackageDescription

let package = Package(
    name: "IDEStudioShared",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "IDEStudioShared", targets: ["IDEStudioShared"]),
    ],
    targets: [
        .target(name: "IDEStudioShared"),
        .testTarget(name: "IDEStudioSharedTests", dependencies: ["IDEStudioShared"]),
    ]
)
