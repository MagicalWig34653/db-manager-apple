// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// A functional core with a required external anchor. No app/OS trust gate is implied.
/// Actor methods perform bounded synchronous crypto/I/O without actor reentrancy.
public actor VaultSession {
    public static let maximumRootUses: UInt64 = 1 << 20
    public static func newSlotIdentifier() throws -> String { try VaultCodec.hex(VaultCodec.random(16)) }
    private let rootURL: URL
    private let slot: String
    private let anchorStore: any VaultAnchorStore
    private let injection: (@Sendable (VaultFailurePoint) throws -> Void)?
    private var store: AtomicStore?
    private var anchor: VaultAnchor?
    private var file: VaultFile?
    private var rootKey: Data?
    private var payloads: [Data] = []
    private var draft = false

    public init(root: URL, slot: String, anchor: any VaultAnchorStore,
                failureInjection: (@Sendable (VaultFailurePoint) throws -> Void)? = nil) {
        rootURL = root; self.slot = slot; anchorStore = anchor; injection = failureInjection
    }

    public func lock() {
        file = nil; rootKey = nil; payloads = []; draft = false; anchor = nil
        store?.close(); store = nil
    }

    public func records() throws -> [VaultRecord] {
        guard let file, !draft else { throw StorageError.locked }
        return zip(file.entries, payloads).map { VaultRecord(id: $0.0.id, revision: $0.0.revision, payload: $0.1) }
    }

    /// Missing anchors never silently enroll an existing portable file.
    public func open(factor: UnlockFactor) throws {
        lock()
        do {
            try initialize()
            guard let active = anchor?.active, let data = try store?.read() else { throw StorageError.conflict }
            let (v, key, values) = try VaultEditing.authenticated(data, factor: factor)
            guard try snapshot(v, data: data) == active else { throw StorageError.conflict }
            file = v; rootKey = key; payloads = values
        } catch { lock(); throw error }
    }

    /// The returned recovery material is ephemeral. Nothing is persisted until both readbacks.
    public func beginCreate(password: String, payloads: [Data]) throws -> SetupMaterial {
        lock()
        do {
            guard !password.utf8.isEmpty, password.utf8.count <= 1024,
                payloads.count <= VaultCodec.maxEntries, payloads.allSatisfy({ $0.count <= VaultCodec.maxPayloadBytes }) else { throw StorageError.limit }
            try initialize()
            guard anchor?.active == nil, try store?.read() == nil else { throw StorageError.conflict }
            if anchor == nil {
                let initial = VaultAnchor(sequence: 1, vaultID: try VaultCodec.hex(VaultCodec.random(16)), active: nil, pending: nil, reservedUses: [:])
                try anchorStore.compareExchange(slot: slot, expected: nil, replacement: initial); anchor = initial
            }
            try reserve(epoch: 1, generation: 1, count: UInt64(payloads.count + 2))
            let (v, recovery) = try VaultCodec.create(password: password, payloads: payloads, vaultID: anchor!.vaultID)
            let (_, key, verified) = try VaultEditing.authenticated(VaultCodec.canonical(v), factor: .recovery(recovery))
            file = v; rootKey = key; self.payloads = verified; draft = true
            return SetupMaterial(vaultID: v.vault_id, recovery: recovery)
        } catch { lock(); throw error }
    }

    /// One surviving old factor permits migration to NEW independent factors and a NEW identity.
    /// The source is never written. Recovery readback of the new material remains mandatory.
    public func beginMigration(source: Data, factor: UnlockFactor, newPassword: String) throws -> SetupMaterial {
        lock()
        let (_, _, values) = try VaultEditing.authenticated(source, factor: factor)
        return try beginCreate(password: newPassword, payloads: values)
    }

    public func confirmCreate(password: String, recovery: Data) throws {
        guard draft, let file, let rootKey else { throw StorageError.locked }
        // Failure here keeps the unsaved draft available for a corrected readback.
        let data = try VaultCodec.canonical(file)
        do {
            _ = try VaultEditing.authenticated(data, factor: .password(password))
            _ = try VaultEditing.authenticated(data, factor: .recovery(recovery))
        } catch is CancellationError { lock(); throw CancellationError() }
        do { try persist(file, key: rootKey, values: payloads) }
        catch { lock(); throw error }
    }

    public func update(_ edits: [VaultEdit]) throws {
        guard !draft, var target = file, let rootKey else { throw StorageError.locked }
        try VaultEditing.validate(edits, previous: target)
        guard target.generation < UInt32.max else { throw StorageError.limit }
        do {
            try reserve(epoch: target.epoch, generation: target.generation + 1, count: UInt64(edits.count))
            let previous = target; target.generation += 1
            target.entries = try VaultEditing.entries(edits, previous: previous, target: target, root: rootKey)
            target.mac = try VaultCodec.mac(target, root: rootKey).base64EncodedString()
            try persist(target, key: rootKey, values: edits.map(\.payload))
        } catch { lock(); throw error }
    }

    /// Retaining old factors requires proving BOTH; a missing factor uses migration instead.
    public func rotate(password: String, recovery: Data) throws {
        guard !draft, let file, let rootKey else { throw StorageError.locked }
        guard file.epoch < UInt32.max, file.generation < UInt32.max else { throw StorageError.limit }
        let data = try VaultCodec.canonical(file)
        _ = try VaultEditing.authenticated(data, factor: .password(password))
        _ = try VaultEditing.authenticated(data, factor: .recovery(recovery))
        let edits = zip(file.entries, payloads).map { VaultEdit(id: $0.0.id, payload: $0.1) }
        try VaultEditing.validate(edits, previous: file)
        do {
            try reserve(epoch: file.epoch + 1, generation: file.generation + 1, count: UInt64(edits.count + 2))
            let (target, key) = try VaultEditing.rotate(file, root: rootKey, edits: edits, password: password, recovery: recovery)
            // Independently read back BOTH freshly wrapped factors before preparing persistence.
            let candidate = try VaultCodec.canonical(target)
            _ = try VaultEditing.authenticated(candidate, factor: .password(password))
            _ = try VaultEditing.authenticated(candidate, factor: .recovery(recovery))
            try persist(target, key: key, values: payloads)
        } catch { lock(); throw error }
    }

    private func snapshot(_ v: VaultFile, data: Data) throws -> VaultSnapshot {
        guard v.vault_id == anchor?.vaultID else { throw StorageError.conflict }
        return VaultSnapshot(vaultID: v.vault_id, epoch: v.epoch, generation: v.generation, sha256: AtomicStore.digest(data))
    }
    private func point(_ value: VaultFailurePoint) throws {
        try Task.checkCancellation(); try injection?(value)
    }
    private func change(_ replacement: VaultAnchor) throws {
        try anchorStore.compareExchange(slot: slot, expected: anchor, replacement: replacement)
        anchor = replacement
    }
    private func next(_ state: VaultAnchor) throws -> VaultAnchor {
        guard state.sequence < UInt64.max else { throw StorageError.limit }
        var value = state; value.sequence += 1; return value
    }
    private func reserve(epoch: UInt32, generation: UInt32, count: UInt64) throws {
        try Task.checkCancellation()
        guard let anchor, let store, anchor.pending == nil, anchor.reservedUses.count < 64 || anchor.reservedUses[epoch] != nil else { throw StorageError.conflict }
        var value = try next(anchor)
        let used = value.reservedUses[epoch] ?? 0
        guard used <= Self.maximumRootUses, count <= Self.maximumRootUses - used else { throw StorageError.limit }
        value.reservedUses[epoch] = used + count
        value.pending = VaultPending(epoch: epoch, generation: generation, temporaryName: try store.temporaryName(), prepared: nil)
        try change(value)
        try point(.afterReservation)
    }
    private func initialize() throws {
        let storage = try AtomicStore(root: rootURL, slot: slot); store = storage
        anchor = try anchorStore.load(slot: slot)
        let bytes = try storage.read()
        if var state = anchor {
            _ = try VaultCodec.identifier(state.vaultID)
            guard state.sequence > 0, state.reservedUses.count <= 64,
                state.reservedUses.allSatisfy({ $0.key > 0 && $0.value <= Self.maximumRootUses }) else { throw StorageError.conflict }
            if let active = state.active {
                guard active.vaultID == state.vaultID, active.epoch > 0, active.generation > 0,
                      state.reservedUses[active.epoch] != nil else { throw StorageError.conflict }
            }
            if let pending = state.pending {
                guard state.reservedUses[pending.epoch] != nil else { throw StorageError.conflict }
                if let active = state.active {
                    guard active.generation < UInt32.max, pending.generation == active.generation + 1,
                        pending.epoch == active.epoch || (active.epoch < UInt32.max && pending.epoch == active.epoch + 1) else { throw StorageError.conflict }
                } else {
                    guard pending.epoch == 1, pending.generation == 1 else { throw StorageError.conflict }
                }
                if let prepared = pending.prepared, let bytes, AtomicStore.digest(bytes) == prepared.sha256 {
                    guard prepared.vaultID == state.vaultID, prepared.epoch == pending.epoch,
                          prepared.generation == pending.generation else { throw StorageError.conflict }
                    state.active = prepared
                    // A rename may have preceded a crash before its directory sync.
                    try storage.syncDirectory()
                } else {
                    guard try matches(bytes, state.active) else { throw StorageError.conflict }
                }
                try storage.discard(pending.temporaryName)
                state = try next(state); state.pending = nil
                try change(state)
            }
            guard try matches(bytes, anchor?.active) else { throw StorageError.conflict }
        } else if bytes != nil { throw StorageError.conflict }
    }
    private func matches(_ data: Data?, _ expected: VaultSnapshot?) throws -> Bool {
        guard let expected else { return data == nil }
        guard let data else { return false }
        let parsed = try VaultCodec.parse(data)
        return try snapshot(parsed, data: data) == expected
    }
    private func persist(_ target: VaultFile, key: Data, values: [Data]) throws {
        guard let store, let current = anchor, let pending = current.pending,
            pending.epoch == target.epoch, pending.generation == target.generation else { throw StorageError.conflict }
        let data = try VaultCodec.canonical(target)
        _ = try VaultCodec.parse(data)
        guard try matches(store.read(), current.active) else { throw StorageError.conflict }
        try store.stage(data, name: pending.temporaryName)
        try point(.afterStaging)
        var prepared = try next(current)
        prepared.pending?.prepared = try snapshot(target, data: data)
        try change(prepared)
        try point(.afterPrepared)
        guard try matches(store.read(), prepared.active) else { throw StorageError.conflict }
        try store.install(pending.temporaryName)
        try point(.afterRename)
        try store.syncDirectory()
        try point(.afterDirectorySync)
        var committed = try next(prepared)
        committed.active = prepared.pending?.prepared; committed.pending = nil
        try change(committed)
        try point(.afterFinalization)
        self.file = target; rootKey = key; payloads = values; draft = false
    }
}
