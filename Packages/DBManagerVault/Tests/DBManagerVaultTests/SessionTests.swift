// SPDX-License-Identifier: AGPL-3.0-only
import Darwin
import Foundation
import Testing
@testable import DBManagerVault

// Functional fixture ONLY: memory is not an independent durable rollback anchor.
final class SyntheticAnchor: VaultAnchorStore, @unchecked Sendable {
    private let mutex = NSLock()
    private var value: VaultAnchor?
    func load(slot: String) throws -> VaultAnchor? { mutex.lock(); defer { mutex.unlock() }; return value }
    func compareExchange(slot: String, expected: VaultAnchor?, replacement: VaultAnchor) throws {
        mutex.lock(); defer { mutex.unlock() }
        guard value == expected else { throw StorageError.conflict }; value = replacement
    }
    func mutate(_ change: (inout VaultAnchor) -> Void) {
        mutex.lock(); defer { mutex.unlock() }; if value != nil { change(&value!) }
    }
}
let syntheticPassword = "synthetic strong master password, never a real secret"
let syntheticSlot = "000102030405060708090a0b0c0d0e0f"
let originalPayload = Data("synthetic original".utf8)
func privateRoot() throws -> URL {
    // Foundation may keep the system /var alias; resolve only the trusted OS temp parent.
    guard let parent = realpath(FileManager.default.temporaryDirectory.path, nil) else { throw StorageError.io }
    defer { free(parent) }
    let root = URL(fileURLWithPath: String(cString: parent)).appendingPathComponent("dbmanager-s2a-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    return root
}
func prepared(_ root: URL, _ anchor: SyntheticAnchor) async throws -> (VaultSession, Data) {
    let session = VaultSession(root: root, slot: syntheticSlot, anchor: anchor)
    let material = try await session.beginCreate(password: syntheticPassword, payloads: [originalPayload])
    try await session.confirmCreate(password: syntheticPassword, recovery: material.recovery)
    return (session, material.recovery)
}

@Test func portableFixturesRemainInteroperable() throws {
    for language in ["go", "swift"] {
        let root = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/" + language)
        let data = try Data(contentsOf: root.appendingPathComponent("vault.json"))
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("synthetic-secrets.json"))) as! [String: Any]
        let password = fixture["password"] as! String
        let recovery = Data(base64Encoded: fixture["recovery"] as! String)!
        let expected = (fixture["plaintexts"] as! [String]).map { Data(base64Encoded: $0)! }
        #expect(try VaultCodec.unlock(data, password: password) == expected)
        #expect(try VaultCodec.unlock(data, recovery: recovery) == expected)
    }
    let notices = try VaultLicenses.originalTexts()
    #expect(notices.count == 2)
    #expect(notices["AGPL-3.0-only.txt"]!.contains("GNU AFFERO GENERAL PUBLIC LICENSE"))
    #expect(notices["Argon2-LICENSE.txt"]!.contains("Apache License"))
}

@Test func setupRequiresIndependentReadbacksAndPrivateFiles() async throws {
    let root = try privateRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let anchor = SyntheticAnchor(); let session = VaultSession(root: root, slot: syntheticSlot, anchor: anchor)
    let setup = try await session.beginCreate(password: syntheticPassword, payloads: [originalPayload])
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(syntheticSlot + ".vault").path))
    do { try await session.confirmCreate(password: "wrong", recovery: setup.recovery); Issue.record("Accepted wrong readback") } catch {}
    do { try await session.confirmCreate(password: syntheticPassword, recovery: Data(repeating: 0, count: 32)); Issue.record("Accepted wrong recovery") } catch {}
    do { _ = try await session.records(); Issue.record("Exposed unsaved draft") } catch {}
    try await session.confirmCreate(password: syntheticPassword, recovery: setup.recovery)
    #expect(try await session.records().map(\.payload) == [originalPayload])
    let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(syntheticSlot + ".vault").path)
    #expect((attributes[.posixPermissions] as! NSNumber).intValue == 0o600)
    await session.lock()
    try await session.open(factor: .recovery(setup.recovery))
    #expect(try await session.records().map(\.payload) == [originalPayload])
    await session.lock()
}

@Test func updatesCounterRotationAndRollbackAreFailClosed() async throws {
    let root = try privateRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let anchor = SyntheticAnchor(); let (session,recovery) = try await prepared(root, anchor)
    let path = root.appendingPathComponent(syntheticSlot + ".vault")
    let old = try Data(contentsOf: path)
    let record = try await session.records()[0]
    try await session.update([VaultEdit(id: record.id, payload: Data())])
    #expect(try anchor.load(slot: syntheticSlot)?.reservedUses[1] == 4)
    #expect(try await session.records()[0].revision == 2)
    #expect(try await session.records()[0].payload == Data())
    let current = try Data(contentsOf: path)
    await session.lock()
    // Preserve the inode/private mode; simulate an attacker replaying valid older bytes.
    try old.write(to: path)
    do { try await session.open(factor: .password(syntheticPassword)); Issue.record("Accepted valid old file") } catch {}
    try current.write(to: path)
    try await session.open(factor: .password(syntheticPassword))
    await session.lock()
    anchor.mutate { $0.reservedUses[1] = VaultSession.maximumRootUses }
    try await session.open(factor: .password(syntheticPassword))
    do { try await session.update([VaultEdit(id: record.id, payload: originalPayload)]); Issue.record("Exceeded root budget") } catch {}
    try await session.open(factor: .recovery(recovery))
    do { try await session.rotate(password: "lost or incorrect", recovery: recovery); Issue.record("Retained unknown old factor") } catch {}
    try await session.rotate(password: syntheticPassword, recovery: recovery)
    #expect(try anchor.load(slot: syntheticSlot)?.active?.epoch == 2)
    #expect(try anchor.load(slot: syntheticSlot)?.reservedUses[1] == VaultSession.maximumRootUses)
    #expect(try anchor.load(slot: syntheticSlot)?.reservedUses[2] == 3)
    await session.lock()
    try await session.open(factor: .password(syntheticPassword)); await session.lock()
    try await session.open(factor: .recovery(recovery)); await session.lock()
}

@Test func crashBoundariesRetainOldOrExactlyPreparedNewBytesAndBurnUses() async throws {
    for point in [VaultFailurePoint.afterReservation,.afterStaging,.afterPrepared,.afterRename,.afterDirectorySync,.afterFinalization] {
        let root = try privateRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let anchor = SyntheticAnchor(); let (initial,recovery) = try await prepared(root, anchor)
        let id = try await initial.records()[0].id
        await initial.lock()
        let broken = VaultSession(root: root, slot: syntheticSlot, anchor: anchor, failureInjection: { phase in
            if phase == point { throw StorageError.io }
        })
        try await broken.open(factor: .recovery(recovery))
        let new = Data("synthetic updated".utf8)
        do { try await broken.update([VaultEdit(id: id, payload: new)]); Issue.record("Fault did not stop commit") } catch {}
        let recovered = VaultSession(root: root, slot: syntheticSlot, anchor: anchor)
        try await recovered.open(factor: .recovery(recovery))
        let installed = [.afterRename,.afterDirectorySync,.afterFinalization].contains(point)
        #expect(try await recovered.records()[0].payload == (installed ? new : originalPayload))
        #expect(try anchor.load(slot: syntheticSlot)?.reservedUses[1] == 4)
        #expect(try anchor.load(slot: syntheticSlot)?.pending == nil)
        try await recovered.update([VaultEdit(id: id, payload: originalPayload)])
        #expect(try anchor.load(slot: syntheticSlot)?.reservedUses[1] == 5)
        await recovered.lock()
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasSuffix(".pending") })
    }
}

@Test func cancellationReleasesLockButDoesNotRefundReservation() async throws {
    let root = try privateRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let anchor = SyntheticAnchor(); let (initial,recovery) = try await prepared(root, anchor)
    let id = try await initial.records()[0].id; await initial.lock()
    let cancelled = VaultSession(root: root, slot: syntheticSlot, anchor: anchor, failureInjection: { point in
        if point == .afterStaging { withUnsafeCurrentTask { $0?.cancel() } }
    })
    try await cancelled.open(factor: .recovery(recovery))
    let task = Task { try await cancelled.update([VaultEdit(id: id, payload: Data())]) }
    do { try await task.value; Issue.record("Accepted cancelled write") } catch {}
    let recovered = VaultSession(root: root, slot: syntheticSlot, anchor: anchor)
    try await recovered.open(factor: .recovery(recovery))
    #expect(try await recovered.records()[0].payload == originalPayload)
    #expect(try anchor.load(slot: syntheticSlot)?.reservedUses[1] == 4)
    await recovered.lock()
}

@Test func recoveryMigrationWithLostPasswordCreatesNewIdentityAndFactors() async throws {
    let sourceRoot = try privateRoot(); let targetRoot = try privateRoot()
    defer { try? FileManager.default.removeItem(at: sourceRoot); try? FileManager.default.removeItem(at: targetRoot) }
    let oldAnchor = SyntheticAnchor(); let (source,oldRecovery) = try await prepared(sourceRoot, oldAnchor)
    let original = try Data(contentsOf: sourceRoot.appendingPathComponent(syntheticSlot + ".vault")); await source.lock()
    let targetAnchor = SyntheticAnchor(); let target = VaultSession(root: targetRoot, slot: syntheticSlot, anchor: targetAnchor)
    do { _ = try await target.beginMigration(source: original, factor: .recovery(oldRecovery), newPassword: syntheticPassword); Issue.record("Retained old password during migration") } catch {}
    #expect(try targetAnchor.load(slot: syntheticSlot) == nil)
    let setup = try await target.beginMigration(source: original, factor: .recovery(oldRecovery), newPassword: "new synthetic independent password")
    #expect(setup.vaultID != (try VaultCodec.parse(original)).vault_id)
    #expect(setup.recovery != oldRecovery)
    do { try await target.confirmCreate(password: "new synthetic independent password", recovery: oldRecovery); Issue.record("Old recovery opened new root") } catch {}
    try await target.confirmCreate(password: "new synthetic independent password", recovery: setup.recovery)
    await target.lock()
    try await target.open(factor: .password("new synthetic independent password")); await target.lock()
    try await target.open(factor: .recovery(setup.recovery)); await target.lock()
    #expect(try Data(contentsOf: sourceRoot.appendingPathComponent(syntheticSlot + ".vault")) == original)
}

@Test func missingAnchorSymlinksHardlinksAndConcurrentSessionsAreRejected() async throws {
    let root = try privateRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let anchor = SyntheticAnchor(); let (session,recovery) = try await prepared(root, anchor)
    let other = VaultSession(root: root, slot: syntheticSlot, anchor: anchor)
    do { try await other.open(factor: .recovery(recovery)); Issue.record("Acquired concurrent writer") } catch {}
    await session.lock()
    let noAnchor = VaultSession(root: root, slot: syntheticSlot, anchor: SyntheticAnchor())
    do { try await noAnchor.open(factor: .recovery(recovery)); Issue.record("Silently enrolled old root") } catch {}
    let path = root.appendingPathComponent(syntheticSlot + ".vault")
    let saved = root.appendingPathComponent("original")
    let data = try Data(contentsOf: path)
    try FileManager.default.moveItem(at: path, to: saved)
    try FileManager.default.createSymbolicLink(at: path, withDestinationURL: saved)
    do { try await session.open(factor: .recovery(recovery)); Issue.record("Accepted symlink") } catch {}
    try FileManager.default.removeItem(at: path)
    try FileManager.default.linkItem(at: saved, to: path)
    do { try await session.open(factor: .recovery(recovery)); Issue.record("Accepted hardlink") } catch {}
    #expect(try Data(contentsOf: saved) == data)
    try FileManager.default.removeItem(at: path)
    try FileManager.default.moveItem(at: saved, to: path)
    try await session.open(factor: .recovery(recovery)); await session.lock()
}

@Test func staleAnchorCASAndGenerationExhaustionPreserveOriginalBytes() async throws {
    let root = try privateRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let anchor = SyntheticAnchor(); let (session,recovery) = try await prepared(root, anchor)
    let path = root.appendingPathComponent(syntheticSlot + ".vault")
    let original = try Data(contentsOf: path)
    anchor.mutate { $0.sequence += 1 }
    do { try await session.update([]); Issue.record("Accepted stale CAS") } catch {}
    #expect(try Data(contentsOf: path) == original)
    let (parsed,key,_) = try VaultEditing.authenticated(original, factor: .recovery(recovery))
    var exhausted = parsed; exhausted.generation = .max
    exhausted.mac = try VaultCodec.mac(exhausted, root: key).base64EncodedString()
    let bytes = try VaultCodec.canonical(exhausted)
    try bytes.write(to: path)
    anchor.mutate { $0.active = VaultSnapshot(vaultID: exhausted.vault_id, epoch: exhausted.epoch, generation: .max, sha256: AtomicStore.digest(bytes)) }
    try await session.open(factor: .recovery(recovery))
    do { try await session.update([]); Issue.record("Wrapped generation") } catch {}
    do { try await session.rotate(password: syntheticPassword, recovery: recovery); Issue.record("Rotated past generation limit") } catch {}
    #expect(try Data(contentsOf: path) == bytes)
    await session.lock()
}

@Test func modifiedPreparedCandidateIsNeverSilentlyReplaced() async throws {
    let root = try privateRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let anchor = SyntheticAnchor(); let (initial,recovery) = try await prepared(root, anchor); await initial.lock()
    let broken = VaultSession(root: root, slot: syntheticSlot, anchor: anchor, failureInjection: { point in
        if point == .afterRename { throw StorageError.io }
    })
    try await broken.open(factor: .recovery(recovery))
    do { try await broken.update([]); Issue.record("Did not inject failure") } catch {}
    let path = root.appendingPathComponent(syntheticSlot + ".vault")
    var corrupt = try Data(contentsOf: path); corrupt[corrupt.count - 1] = 0
    try corrupt.write(to: path)
    let recovered = VaultSession(root: root, slot: syntheticSlot, anchor: anchor)
    do { try await recovered.open(factor: .recovery(recovery)); Issue.record("Accepted unknown crash contents") } catch {}
    #expect(try Data(contentsOf: path) == corrupt)
    #expect(try anchor.load(slot: syntheticSlot)?.pending != nil)
}

@Test func rollbackOfBothSyntheticAnchorAndFileHasNoTrustedFreshnessOracle() async throws {
    let root = try privateRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let anchor = SyntheticAnchor(); let (session,recovery) = try await prepared(root, anchor)
    let path = root.appendingPathComponent(syntheticSlot + ".vault")
    let oldFile = try Data(contentsOf: path)
    let oldAnchor = try anchor.load(slot: syntheticSlot)!
    try await session.update([]); await session.lock()
    try oldFile.write(to: path)
    anchor.mutate { $0 = oldAnchor }
    // This intentionally succeeds: a rollbackable test provider is NOT a production anchor.
    try await session.open(factor: .recovery(recovery))
    #expect(try await session.records()[0].payload == originalPayload)
    await session.lock()
}

@Test func modifiedStagingFileNeverReturnsSuccessfulCommit() async throws {
    for phase in [VaultFailurePoint.afterPrepared, .afterDirectorySync] {
    let root = try privateRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let anchor = SyntheticAnchor(); let (initial,recovery) = try await prepared(root, anchor)
    let original = try Data(contentsOf: root.appendingPathComponent(syntheticSlot + ".vault")); await initial.lock()
    let session = VaultSession(root: root, slot: syntheticSlot, anchor: anchor, failureInjection: { point in
        if point == phase {
            let name = phase == .afterPrepared ? try anchor.load(slot: syntheticSlot)!.pending!.temporaryName : syntheticSlot + ".vault"
            try Data("synthetic damaged stage".utf8).write(to: root.appendingPathComponent(name))
        }
    })
    try await session.open(factor: .recovery(recovery))
    do { try await session.update([]); Issue.record("Reported corrupt staging data committed") } catch {}
    if phase == .afterPrepared { #expect(try Data(contentsOf: root.appendingPathComponent(syntheticSlot + ".vault")) == original) }
    #expect(try anchor.load(slot: syntheticSlot)?.active?.generation == 1)
    await session.lock()
    }
}

@Test func inputAndFileBoundsUnsafeModesAndManagedNamesAreEnforced() async throws {
    let root = try privateRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let anchor = SyntheticAnchor()
    let badName = VaultSession(root: root, slot: "../escape", anchor: anchor)
    do { _ = try await badName.beginCreate(password: syntheticPassword, payloads: []); Issue.record("Accepted unmanaged name") } catch {}
    let session = VaultSession(root: root, slot: syntheticSlot, anchor: anchor)
    for values in [Array(repeating: Data(), count: 65), [Data(repeating: 1, count: 65537)]] {
        do { _ = try await session.beginCreate(password: syntheticPassword, payloads: values); Issue.record("Accepted payload bounds") } catch {}
    }
    #expect(try anchor.load(slot: syntheticSlot) == nil)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    let (active,recovery) = try await prepared(root, anchor); await active.lock()
    let path = root.appendingPathComponent(syntheticSlot + ".vault")
    let old = try Data(contentsOf: path)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path.path)
    do { try await session.open(factor: .recovery(recovery)); Issue.record("Accepted public file mode") } catch {}
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    let handle = try FileHandle(forWritingTo: path); try handle.truncate(atOffset: UInt64(VaultCodec.maxFileBytes + 1)); try handle.close()
    do { try await session.open(factor: .recovery(recovery)); Issue.record("Accepted oversize file") } catch {}
    try old.write(to: path)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
    do { try await session.open(factor: .recovery(recovery)); Issue.record("Accepted public root mode") } catch {}
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    try await session.open(factor: .recovery(recovery)); await session.lock()
}
