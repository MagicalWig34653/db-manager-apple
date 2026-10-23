// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

public enum StorageError: Error, Sendable { case invalid, busy, conflict, locked, factor, limit, io, cancelled }

public struct VaultSnapshot: Codable, Equatable, Sendable {
    public let vaultID: String
    public let epoch: UInt32
    public let generation: UInt32
    public let sha256: String
}

public struct VaultPending: Codable, Equatable, Sendable {
    public let epoch: UInt32
    public let generation: UInt32
    public let temporaryName: String
    public var prepared: VaultSnapshot?
}

public struct VaultAnchor: Codable, Equatable, Sendable {
    public var sequence: UInt64
    public let vaultID: String
    public var active: VaultSnapshot?
    public var pending: VaultPending?
    public var reservedUses: [UInt32: UInt64]
}

/// The provider MUST offer durable, independent, atomic CAS and pinned slot identity.
/// No production provider ships in this package. An ordinary file or memory is insufficient.
/// A thrown/uncertain write must be treated as possibly committed; callers re-open to recover.
public protocol VaultAnchorStore: Sendable {
    func load(slot: String) throws -> VaultAnchor?
    func compareExchange(slot: String, expected: VaultAnchor?, replacement: VaultAnchor) throws
}

public enum VaultFailurePoint: String, Sendable {
    case afterReservation, afterStaging, afterPrepared, afterRename, afterDirectorySync, afterFinalization
}

public enum UnlockFactor: Sendable { case password(String), recovery(Data) }
public struct VaultRecord: Sendable { public let id: String; public let revision: UInt32; public let payload: Data }
public struct VaultEdit: Sendable {
    public let id: String?
    public let payload: Data
    public init(id: String? = nil, payload: Data) { self.id = id; self.payload = payload }
}
public struct SetupMaterial: Sendable { public let vaultID: String; public let recovery: Data }
