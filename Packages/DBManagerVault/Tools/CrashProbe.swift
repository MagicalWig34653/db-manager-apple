// SPDX-License-Identifier: AGPL-3.0-only
// Built only in a temporary test package. NEVER use this synthetic file anchor in an app.
import DBManagerVault
import Darwin
import Foundation

final class SyntheticDiskAnchor: VaultAnchorStore, @unchecked Sendable {
    let path: URL
    init(_ path: URL) { self.path = path }
    func load(slot: String) throws -> VaultAnchor? {
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        return try JSONDecoder().decode(VaultAnchor.self, from: Data(contentsOf: path))
    }
    func compareExchange(slot: String, expected: VaultAnchor?, replacement: VaultAnchor) throws {
        guard try load(slot: slot) == expected else { throw StorageError.conflict }
        try JSONEncoder().encode(replacement).write(to: path, options: .atomic)
    }
}

@main struct CrashProbe {
    static func main() async throws {
        let arguments = CommandLine.arguments
        let base = URL(fileURLWithPath: arguments[1])
        let mode = arguments[2]
        let slot = "000102030405060708090a0b0c0d0e0f"
        let anchor = SyntheticDiskAnchor(base.appendingPathComponent("synthetic-anchor.json"))
        let session = VaultSession(root: base.appendingPathComponent("managed"), slot: slot, anchor: anchor,
            failureInjection: { point in if point.rawValue == mode { _exit(86) } })
        let password = "synthetic-only test password, not a real secret"
        if mode == "setup" {
            let recovery = try await session.beginCreate(password: password, payloads: [Data("old".utf8)]).recovery
            try await session.confirmCreate(password: password, recovery: recovery)
            await session.lock()
        } else {
            try await session.open(factor: .password(password))
            if mode == "verify-old" || mode == "verify-new" {
                let expected = mode == "verify-old" ? "old" : "new"
                guard try await session.records()[0].payload == Data(expected.utf8),
                    try anchor.load(slot: slot)?.reservedUses[1] == 4,
                    try anchor.load(slot: slot)?.pending == nil else { throw StorageError.conflict }
                await session.lock()
            } else {
                let id = try await session.records()[0].id
                try await session.update([VaultEdit(id: id, payload: Data("new".utf8))])
                throw StorageError.invalid
            }
        }
    }
}
