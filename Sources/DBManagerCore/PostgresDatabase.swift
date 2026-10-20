// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Logging
import NIOCore
import NIOSSL
import PostgresNIO

// Deliberately no Codable, description, persistence or URL/DSN initializer.
public struct PostgresSettings: Sendable {
    public let host: String
    public let port: Int
    public let database: String
    public let username: String
    public let password: String
    public let certificateAuthority: Data?
    public init(host: String, port: Int = 5432, database: String, username: String,
                password: String, certificateAuthority: Data? = nil) {
        self.host = host; self.port = port; self.database = database
        self.username = username; self.password = password; self.certificateAuthority = certificateAuthority
    }
    func configuration(timeout: TimeInterval) throws -> PostgresConnection.Configuration {
        guard !host.isEmpty, host.utf8.count <= 253, !host.contains(where: { $0.isWhitespace }),
              !host.contains("/"), !host.contains("\0"), (1...65535).contains(port),
              !database.isEmpty, !username.isEmpty,
              [database, username, password].allSatisfy({ !$0.contains("\0") && $0.utf8.count <= 4096 }) else {
            throw DatabaseError.invalidConnection
        }
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.certificateVerification = .fullVerification
        tls.minimumTLSVersion = .tlsv12
        if let certificateAuthority {
            guard !certificateAuthority.isEmpty, certificateAuthority.count <= 1_048_576 else { throw DatabaseError.invalidConnection }
            do {
                let certificates = try NIOSSLCertificate.fromPEMBytes(Array(certificateAuthority))
                guard !certificates.isEmpty else { throw DatabaseError.invalidConnection }
                // Explicit operator roots apply only to this connection, never the OS store.
                tls.trustRoots = .certificates(certificates)
            } catch { throw DatabaseError.invalidConnection }
        }
        let context: NIOSSLContext
        do { context = try NIOSSLContext(configuration: tls) }
        catch { throw DatabaseError.invalidConnection }
        var config = PostgresConnection.Configuration(host: host, port: port, username: username,
            password: password, database: database, tls: .require(context))
        config.options.connectTimeout = .milliseconds(Int64(timeout * 1000))
        // Pin certificate identity to the actual user-selected host, including IP literals.
        config.options.tlsServerName = host
        config.options.additionalStartupParameters = [("application_name", "DBManagerApple"), ("client_encoding", "UTF8")]
        return config
    }
}

private struct BackendIdentity: Sendable {
    let pid: Int32
    let started: String
    let database: String
    let username: String
}

private final class QueryConnectionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: PostgresConnection?
    private var identity: BackendIdentity?
    private var cancellationConfirmed = true
    private var stopped = false
    private var cancellation: Task<Void, Never>?
    private var worker: Task<QueryResult, Error>?
    private let configuration: PostgresConnection.Configuration
    private let applicationName: String
    private let logger: Logger
    init(configuration: PostgresConnection.Configuration, applicationName: String, logger: Logger) {
        self.configuration = configuration; self.applicationName = applicationName; self.logger = logger
    }
    func install(_ value: PostgresConnection) {
        lock.lock(); connection = value; let stop = stopped; lock.unlock()
        if stop { let _: EventLoopFuture<Void> = value.close() }
    }
    func installIdentity(_ value: BackendIdentity) { lock.lock(); identity = value; lock.unlock() }
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
        if let connection, let identity {
            cancellationConfirmed = false
            let config = configuration; let name = applicationName; let logger = logger
            cancellation = Task.detached { [self] in
                // Authenticate over verified TLS; never send a raw unauthenticated cancel key.
                let confirmed = await Self.signal(config, identity: identity, applicationName: name, logger: logger)
                setConfirmation(confirmed)
                try? await connection.close()
            }
        } else if let connection { let _: EventLoopFuture<Void> = connection.close() }
        let task = worker
        lock.unlock()
        if cancelWorker { task?.cancel() }
    }
    private func setConfirmation(_ value: Bool) { lock.lock(); cancellationConfirmed = value; lock.unlock() }
    var confirmed: Bool { lock.lock(); defer { lock.unlock() }; return cancellationConfirmed }
    private func cancellationTask() -> Task<Void, Never>? {
        lock.lock(); defer { lock.unlock() }; return cancellation
    }
    func waitForCancellation() async { await cancellationTask()?.value }
    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    private static func signal(_ configuration: PostgresConnection.Configuration, identity: BackendIdentity,
                               applicationName: String, logger: Logger) async -> Bool {
        var config = configuration
        config.options.connectTimeout = .seconds(2)
        config.options.additionalStartupParameters = [("application_name", "DBManagerApple-Cancel"), ("statement_timeout", "2000")]
        var connection: PostgresConnection?
        var confirmed = false
        do {
            let current = try await PostgresConnection.connect(configuration: config, id: 2, logger: logger)
            connection = current
            let deadline = current.eventLoop.scheduleTask(in: .seconds(2)) {
                let _: EventLoopFuture<Void> = current.close()
            }
            defer { deadline.cancel() }
            // PID plus a random per-operation marker avoids signaling an unrelated reused PID.
            let rows = try await current.query("SELECT pg_cancel_backend(pid) FROM pg_catalog.pg_stat_activity WHERE pid=\(identity.pid) AND backend_start::text=\(identity.started) AND datname=\(identity.database) AND usename=\(identity.username) AND application_name=\(applicationName)", logger: logger)
            var count = 0
            for try await row in rows { count += 1; if count > 1 { confirmed = false; break }; confirmed = try row[row.startIndex].decode(Bool.self) }
        } catch { /* Cancellation is best effort; the target is always physically closed below. */ }
        if let connection { try? await connection.close() }
        return confirmed
    }
}

public actor PostgresDatabase {
    private var settings: PostgresSettings?
    private var generation: UInt64 = 0
    private var running = false
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []
    private var active: QueryConnectionGate?
    private let logger = Logger(label: "org.dbmanager.postgres", factory: { _ in SwiftLogNoOpLogHandler() })
    public init() {}

    // Each operation owns and releases a physical connection. No cross-request SQL session.
    public func open(_ settings: PostgresSettings) async throws -> [DatabaseObject] {
        guard !running else { throw DatabaseError.operationInProgress }
        self.settings = nil
        generation &+= 1
        let openingGeneration = generation
        let objects = try await catalog(settings)
        try Task.checkCancellation()
        guard openingGeneration == generation else { throw DatabaseError.canceled }
        self.settings = settings
        return objects
    }
    public func close() async {
        generation &+= 1
        settings = nil
        let gate = active
        gate?.cancel()
        if running { await withCheckedContinuation { closeWaiters.append($0) } }
    }
    public func objects() async throws -> [DatabaseObject] {
        guard let settings else { throw DatabaseError.notOpen }
        return try await catalog(settings)
    }
    private func catalog(_ settings: PostgresSettings) async throws -> [DatabaseObject] {
        let result = try await perform(settings, sql: """
            SELECT n.nspname::text,c.relname::text,CASE WHEN c.relkind IN ('v','m') THEN 'view' ELSE 'table' END::text
            FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
            WHERE c.relkind IN ('r','p','v','m','f') AND n.nspname NOT IN ('pg_catalog','information_schema')
            AND n.nspname NOT LIKE 'pg_toast%' AND n.nspname NOT LIKE 'pg_temp_%'
            ORDER BY n.nspname,c.relname
            """, allowWrites: false, limits: QueryLimits(maxRows: 10_000))
        guard !result.truncated else { throw DatabaseError.resultTooLarge }
        return try result.rows.map { row in
            guard row.count == 3, let schema = row[0].value, let name = row[1].value, let kind = row[2].value else { throw DatabaseError.postgresFailed }
            return DatabaseObject(name: name, kind: kind, schema: schema)
        }
    }
    public func execute(_ sql: String, allowWrites: Bool = false, limits: QueryLimits = QueryLimits()) async throws -> QueryResult {
        guard let settings else { throw DatabaseError.notOpen }
        return try await perform(settings, sql: sql, allowWrites: allowWrites, limits: limits)
    }
    public static func selectSQL(for object: DatabaseObject) -> String {
        func quote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        return "SELECT * FROM " + quote(object.schema) + "." + quote(object.name)
    }
    private func perform(_ settings: PostgresSettings, sql: String, allowWrites: Bool, limits: QueryLimits) async throws -> QueryResult {
        guard !running else { throw DatabaseError.operationInProgress }
        guard limits.maxRows > 0, limits.maxRows <= 10_000, limits.maxCellBytes > 0,
              limits.maxCellBytes <= 1_048_576, limits.maxResultBytes > 0, limits.maxResultBytes <= 8_388_608,
              limits.timeout.isFinite, limits.timeout > 0, limits.timeout <= 60 else { throw DatabaseError.invalidLimits }
        guard !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DatabaseError.emptySQL }
        guard !sql.contains("\0"), sql.utf8.count <= 1_048_576 else { throw DatabaseError.resultTooLarge }
        var configuration = try settings.configuration(timeout: limits.timeout)
        let applicationName = "DBManagerApple:" + UUID().uuidString
        configuration.options.additionalStartupParameters.removeAll { $0.0 == "application_name" }
        configuration.options.additionalStartupParameters.append(("application_name", applicationName))
        let gate = QueryConnectionGate(configuration: configuration, applicationName: applicationName, logger: logger)
        running = true; active = gate
        defer {
            gate.clearWorker(); running = false; active = nil
            let waiters = closeWaiters; closeWaiters = []
            for waiter in waiters { waiter.resume() }
        }
        // A structured race cancels even connecting/authentication and awaits physical close.
        let worker = Task { [logger, configuration] in
            try await Self.run(configuration, sql: sql, allowWrites: allowWrites, limits: limits, gate: gate, logger: logger)
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
    private static func run(_ configuration: PostgresConnection.Configuration, sql: String, allowWrites: Bool,
                            limits: QueryLimits, gate: QueryConnectionGate, logger: Logger) async throws -> QueryResult {
        let start = ContinuousClock.now
        var connection: PostgresConnection?
        do {
            try Task.checkCancellation()
            let current = try await PostgresConnection.connect(configuration: configuration, id: 1, logger: logger)
            connection = current; gate.install(current)
            let result = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await drain(current, sql: allowWrites ? "BEGIN READ WRITE" : "BEGIN READ ONLY", logger: logger)
                let milliseconds = max(1, Int(limits.timeout * 1000))
                try await drain(current, sql: "SET LOCAL statement_timeout = \(milliseconds)", logger: logger)
                // A real query fixes READ ONLY before arbitrary user SQL can SET TRANSACTION.
                let identity = try await current.query("SELECT pg_backend_pid(),backend_start::text,current_database(),current_user::text FROM pg_catalog.pg_stat_activity WHERE pid=pg_backend_pid()", logger: logger)
                var identityCount = 0
                for try await row in identity {
                    identityCount += 1
                    guard identityCount == 1 else { throw DatabaseError.postgresFailed }
                    let cells = Array(row)
                    guard cells.count == 4 else { throw DatabaseError.postgresFailed }
                    gate.installIdentity(BackendIdentity(pid: try cells[0].decode(Int32.self), started: try cells[1].decode(String.self), database: try cells[2].decode(String.self), username: try cells[3].decode(String.self)))
                }
                guard identityCount == 1 else { throw DatabaseError.postgresFailed }
                try Task.checkCancellation()
                let stream = try await current.query(PostgresQuery(unsafeSQL: sql), logger: logger)
                guard stream.columns.count <= 1024 else { throw DatabaseError.resultTooLarge }
                var columns: [Column] = []
                for column in stream.columns {
                    guard column.name.utf8.count <= limits.maxCellBytes else { throw DatabaseError.resultTooLarge }
                    columns.append(Column(name: column.name, databaseType: "\(column.dataType) (OID \(column.dataType.rawValue))"))
                }
                var rows: [[Cell]] = []
                var bytes = try JSONEncoder().encode(columns).count + 256
                guard bytes <= limits.maxResultBytes else { throw DatabaseError.resultTooLarge }
                var truncated = false
                for try await row in stream {
                    try Task.checkCancellation()
                    if rows.count == limits.maxRows { truncated = true; break }
                    let cells = try row.map { try PostgresValues.cell($0, maxBytes: limits.maxCellBytes) }
                    bytes += try JSONEncoder().encode(cells).count + 1
                    guard bytes <= limits.maxResultBytes else { throw DatabaseError.resultTooLarge }
                    rows.append(cells)
                }
                try Task.checkCancellation()
                // Truncated streams are terminated rather than drained without a bound.
                if !truncated { try await drain(current, sql: "COMMIT", logger: logger) }
                let duration = start.duration(to: .now)
                let result = QueryResult(columns: columns, rows: rows, rowsAffected: nil, truncated: truncated,
                    durationMS: Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000))
                guard try JSONEncoder().encode(result).count <= limits.maxResultBytes else { throw DatabaseError.resultTooLarge }
                return result
            } onCancel: { gate.cancel() }
            if result.truncated {
                gate.cancel(cancelWorker: false); await gate.waitForCancellation()
                guard gate.confirmed else { throw DatabaseError.cancellationUnconfirmed }
                try Task.checkCancellation()
            } else if gate.isStopped {
                await gate.waitForCancellation()
                throw gate.confirmed ? DatabaseError.canceled : DatabaseError.cancellationUnconfirmed
            }
            try await current.close()
            return result
        } catch {
            let canceled = Task.isCancelled || gate.isStopped
            if let known = error as? DatabaseError, known == .resultTooLarge || known == .invalidText {
                gate.cancel(cancelWorker: false)
            }
            if gate.isStopped { await gate.waitForCancellation() }
            if let connection { try? await connection.close() }
            if gate.isStopped && !gate.confirmed { throw DatabaseError.cancellationUnconfirmed }
            if canceled { throw DatabaseError.canceled }
            if let known = error as? DatabaseError { throw known }
            if let postgres = error as? PSQLError, postgres.serverInfo?[.sqlState] == "57014" { throw DatabaseError.canceled }
            // Never return driver descriptions, server details, SQL or credentials.
            if connection == nil { throw DatabaseError.connectionFailed }
            throw DatabaseError.postgresFailed
        }
    }
    private static func drain(_ connection: PostgresConnection, sql: String, logger: Logger) async throws {
        let stream = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)
        var count = 0
        for try await _ in stream {
            count += 1
            guard count <= 1 else { throw DatabaseError.postgresFailed }
        }
    }
}
