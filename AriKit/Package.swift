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
    targets: [
        .target(name: "AriKit", swiftSettings: swiftSettings),
        .testTarget(name: "AriKitTests", dependencies: ["AriKit"], swiftSettings: swiftSettings),
    ]
)
