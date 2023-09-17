// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RuleKit",
    platforms: [.iOS(.v14), .watchOS(.v7), .tvOS(.v14),  .macOS(.v11)],
    products: [
        .library(name: "RuleKit", targets: ["RuleKit"]),
    ],
    targets: [
        .target(
            name: "RuleKit",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]),
        .testTarget(name: "RuleKitTests", dependencies: ["RuleKit"]),
    ]
)
