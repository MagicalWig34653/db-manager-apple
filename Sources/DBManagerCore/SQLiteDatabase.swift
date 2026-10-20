// SPDX-License-Identifier: AGPL-3.0-only
import CSQLite
import Foundation

private final class DatabaseHandle {
    let pointer: OpaquePointer
    let url: URL
    let scoped: Bool
    init(pointer: OpaquePointer, url: URL, scoped: Bool) {
        self.pointer = pointer; self.url = url; self.scoped = scoped
    }
    deinit {
        sqlite3_close_v2(pointer)
        if scoped { url.stopAccessingSecurityScopedResource() }
    }
}

// Cancellation may arrive from another executor while SQLite runs synchronously.
// The lock protects the only mutable field; the deadline never changes.
private final class CancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var canceled = false
    private let deadline: TimeInterval
    init(timeout: TimeInterval) { deadline = ProcessInfo.processInfo.systemUptime + timeout }
    func cancel() { lock.lock(); canceled = true; lock.unlock() }
    var shouldStop: Bool {
        lock.lock(); let value = canceled; lock.unlock()
        return value || ProcessInfo.processInfo.systemUptime >= deadline
    }
}

private final class AuthorizationPolicy {
    let allowWrites: Bool
    var deniedWrite = false
    init(allowWrites: Bool) { self.allowWrites = allowWrites }
}

public actor SQLiteDatabase {
    private var handle: DatabaseHandle?
    public init() {}

    public func open(_ url: URL, create: Bool = false) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | (create ? SQLITE_OPEN_CREATE : 0)
        let code = sqlite3_open_v2(url.path, &pointer, flags, nil)
        guard code == SQLITE_OK, let pointer else {
            if let pointer { sqlite3_close_v2(pointer) }
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw DatabaseError.cannotOpen
        }
        // Apple omits the extension-loading C API; the authorizer also denies its SQL function.
        sqlite3_limit(pointer, SQLITE_LIMIT_SQL_LENGTH, 1_048_576)
        sqlite3_limit(pointer, SQLITE_LIMIT_LENGTH, 1_048_576)
        sqlite3_busy_timeout(pointer, 200)
        handle = DatabaseHandle(pointer: pointer, url: url, scoped: scoped)
    }

    public func close() { handle = nil }

    public func execute(_ sql: String, allowWrites: Bool = false,
                        limits: QueryLimits = QueryLimits()) async throws -> QueryResult {
        guard limits.maxRows > 0, limits.maxRows <= 10_000,
              limits.maxCellBytes > 0, limits.maxCellBytes <= 1_048_576,
              limits.maxResultBytes > 0, limits.maxResultBytes <= 8_388_608,
              limits.timeout > 0, limits.timeout <= 60, limits.timeout.isFinite else {
            throw DatabaseError.invalidLimits
        }
        let gate = CancellationGate(timeout: limits.timeout)
        return try await withTaskCancellationHandler {
            try run(sql, allowWrites: allowWrites, limits: limits, gate: gate)
        } onCancel: { gate.cancel() }
    }

    public func objects() async throws -> [DatabaseObject] {
        let result = try await execute("SELECT name, type FROM sqlite_schema WHERE type IN ('table','view') AND name NOT GLOB 'sqlite_*' ORDER BY name", limits: QueryLimits(maxRows: 10_000))
        guard !result.truncated else { throw DatabaseError.resultTooLarge }
        return result.rows.compactMap { row in
            guard row.count == 2, let name = row[0].value, let kind = row[1].value else { return nil }
            return DatabaseObject(name: name, kind: kind)
        }
    }

    public static func selectSQL(for name: String) -> String {
        "SELECT * FROM \"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func run(_ sql: String, allowWrites: Bool, limits: QueryLimits,
                     gate: CancellationGate) throws -> QueryResult {
        guard let handle else { throw DatabaseError.notOpen }
        guard !gate.shouldStop else { throw DatabaseError.canceled }
        guard !sql.contains("\0"), sql.utf8.count <= 1_048_576 else { throw DatabaseError.resultTooLarge }
        let db = handle.pointer
        let start = ProcessInfo.processInfo.systemUptime
        let policy = AuthorizationPolicy(allowWrites: allowWrites)
        sqlite3_set_authorizer(db, { context, action, first, second, _, _ in
            guard let context else { return SQLITE_DENY }
            let policy = Unmanaged<AuthorizationPolicy>.fromOpaque(context).takeUnretainedValue()
            if action == SQLITE_ATTACH || action == SQLITE_DETACH { return SQLITE_DENY }
            if action == SQLITE_FUNCTION, let second, String(cString: second).lowercased() == "load_extension" { return SQLITE_DENY }
            // Some PRAGMAs take effect during prepare, before the batch-tail check.
            // Only known metadata reads are admitted, even when writes are enabled.
            if action == SQLITE_PRAGMA {
                let name = first.map { String(cString: $0).lowercased() } ?? ""
                let metadata = ["table_info", "table_xinfo", "index_list", "index_info", "foreign_key_list"]
                let scalarReads = ["database_list", "compile_options", "table_list", "user_version", "schema_version", "page_count", "freelist_count", "encoding"]
                if metadata.contains(name) || (second == nil && scalarReads.contains(name)) { return SQLITE_OK }
                policy.deniedWrite = !policy.allowWrites
                return SQLITE_DENY
            }
            if policy.allowWrites { return SQLITE_OK }
            if action == SQLITE_SELECT || action == SQLITE_READ || action == SQLITE_FUNCTION || action == SQLITE_RECURSIVE { return SQLITE_OK }
            policy.deniedWrite = true
            return SQLITE_DENY
        }, Unmanaged.passUnretained(policy).toOpaque())
        defer { sqlite3_set_authorizer(db, nil, nil); withExtendedLifetime(policy) {} }
        let gatePointer = Unmanaged.passUnretained(gate).toOpaque()
        sqlite3_progress_handler(db, 1_000, { context in
            guard let context else { return 1 }
            return Unmanaged<CancellationGate>.fromOpaque(context).takeUnretainedValue().shouldStop ? 1 : 0
        }, gatePointer)
        defer { sqlite3_progress_handler(db, 0, nil, nil); withExtendedLifetime(gate) {} }
        var statement: OpaquePointer?
        var remainder = ""
        let prepareCode = sql.utf8CString.withUnsafeBufferPointer { buffer in
            var tail: UnsafePointer<CChar>?
            let code = sqlite3_prepare_v2(db, buffer.baseAddress, -1, &statement, &tail)
            if let tail { remainder = String(cString: tail) }
            return code
        }
        defer { if let statement { sqlite3_finalize(statement) } }
        guard prepareCode == SQLITE_OK else {
            if policy.deniedWrite { throw DatabaseError.writesDisabled }
            throw failure(prepareCode, gate: gate)
        }
        guard let statement else { throw DatabaseError.emptySQL }
        guard remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DatabaseError.multipleStatements
        }
        let readOnly = sqlite3_stmt_readonly(statement) != 0
        guard allowWrites || readOnly else { throw DatabaseError.writesDisabled }
        let count = sqlite3_column_count(statement)
        var columns: [Column] = []
        for index in 0..<count {
            columns.append(Column(name: String(cString: sqlite3_column_name(statement, index)),
                                  databaseType: sqlite3_column_decltype(statement, index).map(String.init(cString:)) ?? ""))
        }
        var rows: [[Cell]] = []
        var bytes = try JSONEncoder().encode(columns).count + 256
        guard bytes <= limits.maxResultBytes else { throw DatabaseError.resultTooLarge }
        var truncated = false
        let previousChanges = sqlite3_total_changes64(db)
        while true {
            guard !gate.shouldStop else { throw DatabaseError.canceled }
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw failure(code, gate: gate) }
            if rows.count == limits.maxRows { truncated = true; break }
            var row: [Cell] = []
            for index in 0..<count { row.append(try cell(statement, index: index, maxBytes: limits.maxCellBytes)) }
            bytes += try JSONEncoder().encode(row).count + 1
            guard bytes <= limits.maxResultBytes else { throw DatabaseError.resultTooLarge }
            rows.append(row)
        }
        let result = QueryResult(columns: columns, rows: rows,
                           rowsAffected: readOnly ? nil : String(sqlite3_total_changes64(db) - previousChanges),
                           truncated: truncated,
                           durationMS: Int((ProcessInfo.processInfo.systemUptime - start) * 1_000))
        guard try JSONEncoder().encode(result).count <= limits.maxResultBytes else {
            throw DatabaseError.resultTooLarge
        }
        return result
    }

    private func cell(_ statement: OpaquePointer, index: Int32, maxBytes: Int) throws -> Cell {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_NULL: return Cell(kind: .null)
        case SQLITE_INTEGER: return Cell(kind: .integer, value: String(sqlite3_column_int64(statement, index)))
        case SQLITE_FLOAT: return Cell(kind: .float, value: String(sqlite3_column_double(statement, index)))
        case SQLITE_BLOB:
            let size = Int(sqlite3_column_bytes(statement, index))
            guard size <= maxBytes else { throw DatabaseError.resultTooLarge }
            let data = sqlite3_column_blob(statement, index).map { Data(bytes: $0, count: size) } ?? Data()
            return Cell(kind: .binary, value: data.base64EncodedString())
        default:
            let pointer = sqlite3_column_text(statement, index)
            let size = Int(sqlite3_column_bytes(statement, index))
            guard size <= maxBytes else { throw DatabaseError.resultTooLarge }
            let data = pointer.map { Data(bytes: $0, count: size) } ?? Data()
            guard let text = String(data: data, encoding: .utf8) else { throw DatabaseError.invalidText }
            return Cell(kind: .text, value: text)
        }
    }

    private func failure(_ code: Int32, gate: CancellationGate) -> DatabaseError {
        if gate.shouldStop || code == SQLITE_INTERRUPT { return .canceled }
        if code == SQLITE_BUSY || code == SQLITE_LOCKED { return .busy }
        if code == SQLITE_TOOBIG { return .resultTooLarge }
        return .queryFailed(code)
    }
}
