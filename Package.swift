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
        .package(url: "https://github.com/apple/swift-log.git", from: "1.7.0"),
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
