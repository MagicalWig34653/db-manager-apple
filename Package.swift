// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-only
import PackageDescription

let package = Package(
    name: "DBManagerApple",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "DBManagerCore", targets: ["DBManagerCore"]),
        .executable(name: "DBManagerApp", targets: ["DBManagerApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio.git", exact: "1.33.1"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.104.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", revision: "15e0b9e495786807272dd4891fa4bac76aa43034"),
        .package(url: "https://github.com/apple/swift-log.git", exact: "1.16.1"),
        // Keep the resolved graph buildable with the stable Swift 6.2 CI toolchain.
        .package(url: "https://github.com/apple/swift-collections.git", exact: "1.2.1")
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "DBManagerCore", dependencies: ["CSQLite", .product(name: "PostgresNIO", package: "postgres-nio"), .product(name: "NIOCore", package: "swift-nio"), .product(name: "NIOPosix", package: "swift-nio"), .product(name: "NIOTLS", package: "swift-nio"), .product(name: "NIOSSL", package: "swift-nio-ssl"), .product(name: "Logging", package: "swift-log"), .product(name: "DequeModule", package: "swift-collections")], resources: [.copy("Resources/ThirdParty")]),
        .executableTarget(name: "DBManagerApp", dependencies: ["DBManagerCore"], exclude: ["DBManager.entitlements"]),
        .testTarget(name: "DBManagerCoreTests", dependencies: ["DBManagerCore", .product(name: "NIOCore", package: "swift-nio")]),
        .testTarget(name: "DBManagerAppTests", dependencies: ["DBManagerApp", "DBManagerCore"])
    ]
)
