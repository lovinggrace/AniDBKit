// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AniDBKit",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "AniDBKit", targets: ["AniDBKit"]),
    ],
    targets: [
        .target(name: "AniDBKit"),
        .testTarget(name: "AniDBKitTests", dependencies: ["AniDBKit"]),
    ]
)
