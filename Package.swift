// swift-tools-version: 6.0
// SPDX-License-Identifier: AGPL-3.0-only
import PackageDescription

let package = Package(
    name: "DBManagerApple",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "DBManagerCore", targets: ["DBManagerCore"]),
        .executable(name: "DBManagerApp", targets: ["DBManagerApp"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "DBManagerCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "DBManagerApp", dependencies: ["DBManagerCore"], exclude: ["DBManager.entitlements"]),
        .testTarget(name: "DBManagerCoreTests", dependencies: ["DBManagerCore"]),
        .testTarget(name: "DBManagerAppTests", dependencies: ["DBManagerApp", "DBManagerCore"])
    ]
)
