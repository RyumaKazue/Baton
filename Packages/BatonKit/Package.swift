// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "BatonKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "BatonKit", targets: ["BatonKit"]),
    ],
    targets: [
        .target(name: "BatonKit"),
        .testTarget(name: "BatonKitTests", dependencies: ["BatonKit"]),
    ]
)
