// SPDX-License-Identifier: AGPL-3.0-only
import CryptoKit
import Foundation

enum VaultEditing {
    static func authenticated(_ data: Data, factor: UnlockFactor) throws -> (VaultFile, Data, [Data]) {
        try Task.checkCancellation()
        let v = try VaultCodec.parse(data)
        let payloads: [Data]
        let root: Data
        do {
            switch factor {
            case .password(let password):
                root = try VaultCodec.unseal(VaultCodec.passwordKey(password, kdf: v.password.kdf),
                    aad: VaultCodec.aad(v, purpose: 1), nonce: v.password.nonce, ciphertext: v.password.wrapped_root)
            case .recovery(let recovery):
                guard recovery.count == 32 else { throw StorageError.factor }
                root = try VaultCodec.unseal(VaultCodec.derived(recovery, vault: v, purpose: "recovery"),
                    aad: VaultCodec.aad(v, purpose: 2), nonce: v.recovery.nonce, ciphertext: v.recovery.wrapped_root)
            }
            guard HMAC<SHA256>.isValidAuthenticationCode(try VaultCodec.decode(v.mac, count: 32),
                authenticating: try VaultCodec.manifest(v), using: try VaultCodec.derived(root, vault: v, purpose: "manifest")) else { throw StorageError.factor }
            payloads = try v.entries.map { entry in
                let key = try VaultCodec.unseal(SymmetricKey(data: root), aad: VaultCodec.aad(v, purpose: 3, entry: entry),
                    nonce: entry.key_nonce, ciphertext: entry.wrapped_key)
                return try VaultCodec.unseal(SymmetricKey(data: key), aad: VaultCodec.aad(v, purpose: 4, entry: entry),
                    nonce: entry.payload_nonce, ciphertext: entry.payload)
            }
        } catch is CancellationError { throw CancellationError() }
        catch { throw StorageError.factor }
        try Task.checkCancellation()
        return (v, root, payloads)
    }

    static func validate(_ edits: [VaultEdit], previous: VaultFile) throws {
        guard edits.count <= VaultCodec.maxEntries, edits.allSatisfy({ $0.payload.count <= VaultCodec.maxPayloadBytes }) else { throw StorageError.limit }
        var seen = Set<String>()
        for edit in edits {
            if let id = edit.id {
                guard seen.insert(id).inserted,
                    let old = previous.entries.first(where: { $0.id == id }), old.revision < UInt32.max else { throw StorageError.invalid }
            }
        }
    }

    static func entries(_ edits: [VaultEdit], previous: VaultFile, target: VaultFile, root: Data) throws -> [Entry] {
        try edits.map { edit in
            try Task.checkCancellation()
            let old = previous.entries.first(where: { $0.id == edit.id })
            var entry = Entry(id: try edit.id ?? VaultCodec.hex(VaultCodec.random(16)), revision: old.map { $0.revision + 1 } ?? 1,
                key_nonce: "", wrapped_key: "", payload_nonce: "", payload: "")
            let key = try VaultCodec.random(32)
            (entry.key_nonce, entry.wrapped_key) = try VaultCodec.seal(SymmetricKey(data: root),
                aad: VaultCodec.aad(target, purpose: 3, entry: entry), plaintext: key)
            (entry.payload_nonce, entry.payload) = try VaultCodec.seal(SymmetricKey(data: key),
                aad: VaultCodec.aad(target, purpose: 4, entry: entry), plaintext: edit.payload)
            return entry
        }
    }

    static func rotate(_ previous: VaultFile, root: Data, edits: [VaultEdit], password: String, recovery: Data) throws -> (VaultFile, Data) {
        guard previous.epoch < UInt32.max else { throw StorageError.limit }
        var v = previous; v.epoch += 1; v.generation += 1
        v.password.kdf.salt = try VaultCodec.random(16).base64EncodedString()
        let newRoot = try VaultCodec.random(32)
        (v.password.nonce, v.password.wrapped_root) = try VaultCodec.seal(VaultCodec.passwordKey(password, kdf: v.password.kdf),
            aad: VaultCodec.aad(v, purpose: 1), plaintext: newRoot)
        (v.recovery.nonce, v.recovery.wrapped_root) = try VaultCodec.seal(VaultCodec.derived(recovery, vault: v, purpose: "recovery"),
            aad: VaultCodec.aad(v, purpose: 2), plaintext: newRoot)
        v.entries = try entries(edits, previous: previous, target: v, root: newRoot)
        v.mac = try VaultCodec.mac(v, root: newRoot).base64EncodedString()
        _ = try VaultCodec.parse(VaultCodec.canonical(v))
        return (v, newRoot)
    }
}
