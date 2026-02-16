// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "powersync_flutter_libs",
    platforms: [
        .iOS("13.0"),
        .macOS("10.15")
    ],
    products: [
        .library(name: "powersync-flutter-libs", type: .static, targets: ["powersync_flutter_libs"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/powersync-ja/powersync-sqlite-core-swift.git",
            // Note: Always update podspec as well when updating this.
            exact: "0.4.11"
        )
    ],
    targets: [
        .target(
            name: "powersync_flutter_libs",
            dependencies: [
                .product(name: "PowerSyncSQLiteCore", package: "powersync-sqlite-core-swift")
            ],
            resources: []
        )
    ]
)
