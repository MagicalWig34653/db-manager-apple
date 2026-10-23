// swift-tools-version: 6.0
// SPDX-License-Identifier: AGPL-3.0-only
import PackageDescription
let package = Package(name: "KeychainAnchorGate", platforms: [.macOS(.v14)],
    products: [.executable(name: "keychain-gate", targets: ["KeychainGate"])],
    targets: [.executableTarget(name: "KeychainGate")])
