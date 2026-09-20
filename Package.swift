// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MiddleClick",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .target(
            name: "MultitouchSupportShim",
            path: "Sources/MultitouchSupportShim",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "MiddleClick",
            dependencies: ["MultitouchSupportShim"],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/System/Library/PrivateFrameworks",
                    "-framework", "MultitouchSupport",
                ]),
            ]
        ),
        .testTarget(
            name: "MiddleClickTests",
            dependencies: ["MiddleClick"]
        ),
    ]
)
