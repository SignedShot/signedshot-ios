// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SignedShotSDK",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "SignedShotSDK",
            targets: ["SignedShotSDK"]
        ),
    ],
    targets: [
        .target(
            name: "SignedShotSDK",
            dependencies: []
        ),
        .testTarget(
            name: "SignedShotSDKTests",
            dependencies: ["SignedShotSDK"]
        ),
    ]
)
