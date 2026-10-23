// swift-tools-version: 6.0
// SPDX-License-Identifier: AGPL-3.0-only
import PackageDescription

let package = Package(name: "DBManagerVault", platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "DBManagerVault", targets: ["DBManagerVault"])], targets: [
        .target(name: "CArgon2", path: "Vendor/argon2", exclude: ["LICENSE", "upstream-lock.json"],
                sources: ["src/argon2.c", "src/core.c", "src/encoding.c", "src/ref.c", "src/thread.c", "src/blake2/blake2b.c"],
                publicHeadersPath: "include", cSettings: [.headerSearchPath("src"), .define("ARGON2_NO_THREADS")]),
        .target(name: "DBManagerVault", dependencies: ["CArgon2"], resources: [.copy("Notices")]),
        .testTarget(name: "DBManagerVaultTests", dependencies: ["DBManagerVault"], resources: [.copy("Fixtures")])
    ])
