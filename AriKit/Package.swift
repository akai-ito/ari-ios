// swift-tools-version: 6.2

import PackageDescription

// The app target's concurrency behaviour, minus its main-actor default: AriKit's models and store
// are plain values that any actor can use.
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "AriKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "AriKit", targets: ["AriKit"])
    ],
    dependencies: [
        // Apple's GitHub Markdown parser (cmark-gfm underneath); Ari draws the result itself.
        .package(url: "https://github.com/swiftlang/swift-markdown", from: "0.9.0"),
        // Tests only: a clock the tests move by hand, for heartbeats, backoff and Retry-After.
        .package(url: "https://github.com/pointfreeco/swift-clocks", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "AriKit",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            swiftSettings: swiftSettings),
        .testTarget(
            name: "AriKitTests",
            dependencies: ["AriKit", .product(name: "Clocks", package: "swift-clocks")],
            swiftSettings: swiftSettings),
    ]
)
