// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import NIOCore
import NIOSSL

// Deliberately no Codable, description, persistence or URL/DSN initializer.
public struct MySQLSettings: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "MySQLSettings(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
    public let host: String
    public let port: Int
    public let database: String
    public let username: String
    public let password: String
    public let certificateAuthority: Data?
    public let transportSecurity: MySQLTransportSecurity
    public init(host: String, port: Int = 3306, database: String = "", username: String, password: String,
                certificateAuthority: Data? = nil, transportSecurity: MySQLTransportSecurity = .verifiedTLS) {
        self.host = host; self.port = port; self.database = database; self.username = username
        self.password = password; self.certificateAuthority = certificateAuthority
        self.transportSecurity = transportSecurity
    }

    func configuration(timeout: TimeInterval) throws -> MySQLConnectionConfig {
        guard !host.isEmpty, host.utf8.count <= 253, !host.contains(where: { $0.isWhitespace }),
              !host.contains("/"), !host.contains("\0"), (1...65535).contains(port), !username.isEmpty,
              username.utf8.count <= 128,
              [database, username, password].allSatisfy({ !$0.contains("\0") && $0.utf8.count <= 4096 }) else {
            throw DatabaseError.invalidMySQLConnection
        }
        var context: NIOSSLContext?
        switch transportSecurity {
        case .plaintext, .unverifiedTLS:
            // A CA file contradicts a mode that does not verify; refuse instead of silently ignoring it.
            guard certificateAuthority == nil else { throw DatabaseError.invalidMySQLConnection }
        case .verifiedTLS:
            break
        }
        if transportSecurity.usesTLS {
            var tls = TLSConfiguration.makeClientConfiguration()
            tls.certificateVerification = transportSecurity.verifiesServerIdentity ? .fullVerification : .none
            tls.minimumTLSVersion = .tlsv12
            if let certificateAuthority {
                guard !certificateAuthority.isEmpty, certificateAuthority.count <= 1_048_576 else { throw DatabaseError.invalidMySQLConnection }
                do {
                    let certificates = try NIOSSLCertificate.fromPEMBytes(Array(certificateAuthority))
                    guard !certificates.isEmpty else { throw DatabaseError.invalidMySQLConnection }
                    // Explicit operator roots apply only to this connection, never the OS store.
                    tls.trustRoots = .certificates(certificates)
                } catch { throw DatabaseError.invalidMySQLConnection }
            }
            do { context = try NIOSSLContext(configuration: tls) }
            catch { throw DatabaseError.invalidMySQLConnection }
        }
        return MySQLConnectionConfig(host: host, port: port, database: database, username: username,
                                     password: Array(password.utf8), tls: context, security: transportSecurity,
                                     connectTimeout: timeout)
    }
}

private final class ConnectionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: MySQLConnection?
    private var closed = false
    func set(_ value: MySQLConnection) {
        lock.lock(); connection = value; let stop = closed; lock.unlock()
        if stop { value.forceClose() }
    }
    func close() {
        lock.lock(); closed = true; let value = connection; lock.unlock()
        value?.forceClose()
    }
}

private final class MySQLQueryGate: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: MySQLConnection?
    private var threadID: UInt32?
    private var cancellationConfirmed = true
    private var stopped = false
    private var cancellation: Task<Void, Never>?
    private var worker: Task<QueryResult, Error>?
    private let configuration: MySQLConnectionConfig
    init(configuration: MySQLConnectionConfig) { self.configuration = configuration }

    func install(_ value: MySQLConnection) {
        lock.lock(); connection = value; let stop = stopped; lock.unlock()
        if stop { value.forceClose() }
    }
    func installThread(_ id: UInt32) { lock.lock(); threadID = id; lock.unlock() }
    func installWorker(_ task: Task<QueryResult, Error>) {
        lock.lock(); worker = task; let stop = stopped; lock.unlock()
        if stop { task.cancel() }
    }
    func clearWorker() { lock.lock(); worker = nil; lock.unlock() }
    func cancel(cancelWorker: Bool = true) {
        lock.lock()
        guard !stopped else {
            let task = worker; lock.unlock(); if cancelWorker { task?.cancel() }; return
        }
        stopped = true
        if let connection, let threadID {
            cancellationConfirmed = false
            let config = configuration
            cancellation = Task.detached { [self] in
                // KILL QUERY over a second, equally verified TLS connection; then close the original.
                let confirmed = await Self.kill(config, threadID: threadID)
                setConfirmation(confirmed)
                connection.forceClose()
            }
        } else { connection?.forceClose() }
        let task = worker
        lock.unlock()
        if cancelWorker { task?.cancel() }
    }
    private func setConfirmation(_ value: Bool) { lock.lock(); cancellationConfirmed = value; lock.unlock() }
    var confirmed: Bool { lock.lock(); defer { lock.unlock() }; return cancellationConfirmed }
    private func cancellationTask() -> Task<Void, Never>? { lock.lock(); defer { lock.unlock() }; return cancellation }
    func waitForCancellation() async { await cancellationTask()?.value }
    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    private static func kill(_ configuration: MySQLConnectionConfig, threadID: UInt32) async -> Bool {
        let config = MySQLConnectionConfig(host: configuration.host, port: configuration.port, database: configuration.database,
                                           username: configuration.username, password: configuration.password,
                                           tls: configuration.tls, security: configuration.security, connectTimeout: 2)
        let box = ConnectionBox()
        let deadline = Task { try await Task.sleep(for: .seconds(2)); box.close() }
        defer { deadline.cancel(); box.close() }
        do {
            let connection = try await MySQLConnection.connect(config) { box.set($0) }
            _ = try await connection.query("KILL QUERY \(threadID)", limits: QueryLimits(maxRows: 1))
            return true
        } catch { return false }
    }
}

public actor MySQLDatabase {
    private var settings: MySQLSettings?
    private var generation: UInt64 = 0
    private var running = false
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []
    private var active: MySQLQueryGate?
    public init() {}

    // Each operation owns and releases a physical connection. No cross-request SQL session.
    /// `timeout` bounds connecting, authentication and the initial catalog read together.
    public func open(_ settings: MySQLSettings, timeout: TimeInterval = 10) async throws -> [DatabaseObject] {
        guard !running else { throw DatabaseError.operationInProgress }
        self.settings = nil
        generation &+= 1
        let openingGeneration = generation
        let objects = try await catalog(settings, timeout: timeout)
        try Task.checkCancellation()
        guard openingGeneration == generation else { throw DatabaseError.canceled }
        self.settings = settings
        return objects
    }
    public func close() async {
        generation &+= 1
        settings = nil
        active?.cancel()
        if running { await withCheckedContinuation { closeWaiters.append($0) } }
    }
    public func objects() async throws -> [DatabaseObject] {
        guard let settings else { throw DatabaseError.notOpen }
        return try await catalog(settings)
    }
    /// Schema is the MySQL database name; system schemas are hidden from navigation only.
    private func catalog(_ settings: MySQLSettings, timeout: TimeInterval = 10) async throws -> [DatabaseObject] {
        let result = try await perform(settings, sql: """
            SELECT TABLE_SCHEMA AS s, TABLE_NAME AS n, IF(TABLE_TYPE LIKE '%VIEW%', 'view', 'table') AS k
            FROM information_schema.TABLES
            WHERE TABLE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys')
            ORDER BY TABLE_SCHEMA, TABLE_NAME
            """, allowWrites: false, limits: QueryLimits(maxRows: 10_000, timeout: timeout))
        guard !result.truncated else { throw DatabaseError.resultTooLarge }
        return try result.rows.map { row in
            guard row.count == 3, let schema = row[0].value, let name = row[1].value, let kind = row[2].value else { throw DatabaseError.mysqlProtocolError }
            return DatabaseObject(name: name, kind: kind, schema: schema)
        }
    }
    public func execute(_ sql: String, allowWrites: Bool = false, limits: QueryLimits = QueryLimits()) async throws -> QueryResult {
        guard let settings else { throw DatabaseError.notOpen }
        return try await perform(settings, sql: sql, allowWrites: allowWrites, limits: limits)
    }
    public static func selectSQL(for object: DatabaseObject) -> String {
        func quote(_ value: String) -> String { "`" + value.replacingOccurrences(of: "`", with: "``") + "`" }
        return "SELECT * FROM " + quote(object.schema) + "." + quote(object.name)
    }

    private func perform(_ settings: MySQLSettings, sql: String, allowWrites: Bool, limits: QueryLimits) async throws -> QueryResult {
        guard !running else { throw DatabaseError.operationInProgress }
        guard limits.maxRows > 0, limits.maxRows <= 10_000, limits.maxCellBytes > 0,
              limits.maxCellBytes <= 1_048_576, limits.maxResultBytes > 0, limits.maxResultBytes <= 8_388_608,
              limits.timeout.isFinite, limits.timeout > 0, limits.timeout <= 60 else { throw DatabaseError.invalidLimits }
        guard !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DatabaseError.emptySQL }
        guard !sql.contains("\0"), sql.utf8.count <= 1_048_576 else { throw DatabaseError.resultTooLarge }
        let configuration = try settings.configuration(timeout: limits.timeout)
        let gate = MySQLQueryGate(configuration: configuration)
        running = true; active = gate
        defer {
            gate.clearWorker(); running = false; active = nil
            let waiters = closeWaiters; closeWaiters = []
            for waiter in waiters { waiter.resume() }
        }
        let worker = Task {
            try await Self.run(configuration, sql: sql, allowWrites: allowWrites, limits: limits, gate: gate)
        }
        gate.installWorker(worker)
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: QueryResult.self) { group in
                group.addTask { try await worker.value }
                group.addTask {
                    try await Task.sleep(for: .seconds(limits.timeout))
                    gate.cancel()
                    throw DatabaseError.canceled
                }
                defer { group.cancelAll() }
                do {
                    guard let result = try await group.next() else { throw DatabaseError.canceled }
                    return result
                } catch {
                    if !Task.isCancelled, let known = error as? DatabaseError, known != .canceled && known != .cancellationUnconfirmed { throw known }
                    if Task.isCancelled || gate.isStopped {
                        gate.cancel(); await gate.waitForCancellation()
                        throw gate.confirmed ? DatabaseError.canceled : DatabaseError.cancellationUnconfirmed
                    }
                    throw error
                }
            }
        } onCancel: { gate.cancel() }
    }

    private static func run(_ configuration: MySQLConnectionConfig, sql: String, allowWrites: Bool,
                            limits: QueryLimits, gate: MySQLQueryGate) async throws -> QueryResult {
        let start = ContinuousClock.now
        var connection: MySQLConnection?
        do {
            try Task.checkCancellation()
            let current = try await MySQLConnection.connect(configuration) { gate.install($0) }
            connection = current
            let result = try await withTaskCancellationHandler {
                // Inside the cancellable region: the user deadline also bounds this round trip (review N1).
                gate.installThread(try await current.authenticatedConnectionID())
                try Task.checkCancellation()
                let small = QueryLimits(maxRows: 1, maxCellBytes: 1024, maxResultBytes: 4096, timeout: limits.timeout)
                func statement(_ text: String) async throws {
                    let outcome = try await current.query(text, limits: small)
                    guard outcome.columns.isEmpty else { throw DatabaseError.mysqlProtocolError }
                }
                try await statement("SET SESSION time_zone = '+00:00'")
                // Server-side deadline is a best effort; the client deadline plus KILL QUERY is authoritative.
                // One second slack: the client deadline plus KILL decides first; the server limit is only a backstop.
                let milliseconds = max(1, Int(limits.timeout * 1000)) + 1000
                try? await statement(current.isMariaDB
                    ? "SET SESSION max_statement_time = \(Double(milliseconds) / 1000)"
                    : "SET SESSION max_execution_time = \(milliseconds)")
                try await statement(allowWrites ? "SET SESSION TRANSACTION READ WRITE" : "SET SESSION TRANSACTION READ ONLY")
                if !allowWrites { try await statement("START TRANSACTION READ ONLY") }
                try Task.checkCancellation()
                let outcome = try await current.query(sql, limits: limits)
                try Task.checkCancellation()
                if !allowWrites && !outcome.truncated { try await statement("COMMIT") }
                let columns = outcome.columns.map { Column(name: $0.name, databaseType: $0.typeName) }
                let duration = start.duration(to: .now)
                let result = QueryResult(columns: columns, rows: outcome.rows, rowsAffected: outcome.rowsAffected,
                    truncated: outcome.truncated,
                    durationMS: Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000))
                guard try JSONEncoder().encode(result).count <= limits.maxResultBytes else { throw DatabaseError.resultTooLarge }
                return result
            } onCancel: { gate.cancel() }
            if result.truncated {
                // Remaining rows are never drained: stop the server-side statement, then close.
                gate.cancel(cancelWorker: false); await gate.waitForCancellation()
                guard gate.confirmed else { throw DatabaseError.cancellationUnconfirmed }
                try Task.checkCancellation()
            } else if gate.isStopped {
                await gate.waitForCancellation()
                throw gate.confirmed ? DatabaseError.canceled : DatabaseError.cancellationUnconfirmed
            }
            await current.close()
            return result
        } catch {
            let canceled = Task.isCancelled || gate.isStopped
            if let known = error as? DatabaseError, known == .resultTooLarge || known == .invalidText {
                gate.cancel(cancelWorker: false)
            }
            if gate.isStopped { await gate.waitForCancellation() }
            if let connection { await connection.close() }
            throw failure(error, canceled: canceled, stopped: gate.isStopped, confirmed: gate.confirmed)
        }
    }

    /// Maps a worker failure to the public error. The original cause of our own limit aborts is kept
    /// even if the follow-up KILL could not be confirmed.
    static func failure(_ error: Error, canceled: Bool, stopped: Bool, confirmed: Bool) -> DatabaseError {
        let known = error as? DatabaseError
        if !canceled, let known, known == .resultTooLarge || known == .invalidText { return known }
        if stopped && !confirmed { return .cancellationUnconfirmed }
        if canceled { return .canceled }
        if let known { return known }
        // Never return driver descriptions, server messages, SQL or credentials.
        return .mysqlConnectionFailed
    }
}
