// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RuleKit",
    platforms: [.iOS(.v14), .watchOS(.v7), .tvOS(.v14),  .macOS(.v11)],
    products: [
        .library(name: "RuleKit", targets: ["RuleKit"]),
    ],
    dependencies: [
        // Pinned below 1.9.0 so the package keeps resolving on the Swift 6.0
        // toolchain: swift-log 1.9+ requires Swift tools 6.1, and 1.11+ requires 6.2.
        .package(url: "https://github.com/apple/swift-log.git", "1.7.0"..<"1.9.0"),
    ],
    targets: [
        .target(
            name: "RuleKit",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(name: "RuleKitTests", dependencies: ["RuleKit"]),
    ],
    swiftLanguageModes: [.v6]
)
