// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GradientChat",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(name: "GradientChat", targets: ["GradientChat"]),
    ],
    targets: [
        .target(
            name: "GradientChat",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "GradientChatTests",
            dependencies: ["GradientChat"]
        ),
    ]
)
