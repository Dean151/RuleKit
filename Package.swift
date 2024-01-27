// swift-tools-version: 5.9
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
                .strictConcurrency,
                .warnLongExpressionTypeChecking
            ]),
        .testTarget(name: "RuleKitTests", dependencies: ["RuleKit"]),
    ]
)

extension SwiftSetting {
    static let strictConcurrency = enableUpcomingFeature("StrictConcurrency")
    static let warnLongExpressionTypeChecking = unsafeFlags(
        [
            "-Xfrontend", "-warn-long-expression-type-checking=100",
            "-Xfrontend", "-warn-long-function-bodies=100",
        ],
        .when(configuration: .debug)
    )
}
