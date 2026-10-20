// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Testing
@testable import DBManagerCore

private func withDatabase(_ operation: @Sendable (SQLiteDatabase, URL) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("synthetic.sqlite")
    let database = SQLiteDatabase()
    do {
        try await database.open(url, create: true)
        try await operation(database, url)
        await database.close()
        try FileManager.default.removeItem(at: directory)
    } catch {
        await database.close()
        try? FileManager.default.removeItem(at: directory)
        throw error
    }
}

@Test func preservesPrecisionNullEmptyBinaryAndColumnOrder() async throws {
    try await withDatabase { database, _ in
        let result = try await database.execute("SELECT 9223372036854775807 AS duplicate, NULL AS duplicate, '' AS empty, x'' AS blob_empty, x'00FF' AS blob, 'Grüße 😀' AS unicode, char(65,0,66) AS nul")
        #expect(result.columns.map(\.name) == ["duplicate", "duplicate", "empty", "blob_empty", "blob", "unicode", "nul"])
        #expect(result.rows == [[Cell(kind: .integer, value: "9223372036854775807"), Cell(kind: .null),
                                Cell(kind: .text, value: ""), Cell(kind: .binary, value: ""),
                                Cell(kind: .binary, value: "AP8="), Cell(kind: .text, value: "Grüße 😀"),
                                Cell(kind: .text, value: "A\0B")]])
        let empty = String(data: try JSONEncoder().encode(Cell(kind: .text, value: "")), encoding: .utf8)!
        #expect(empty.contains("\"value\":\"\""))
        let null = String(data: try JSONEncoder().encode(Cell(kind: .null)), encoding: .utf8)!
        #expect(!null.contains("value"))
    }
}

@Test func requiresExplicitWritesAndRejectsPreparationSideEffects() async throws {
    try await withDatabase { database, _ in
        await #expect(throws: DatabaseError.writesDisabled) { try await database.execute("CREATE TABLE test(value INTEGER)") }
        await #expect(throws: DatabaseError.writesDisabled) { try await database.execute("PRAGMA user_version=7") }
        _ = try await database.execute("CREATE TABLE test(value INTEGER)", allowWrites: true)
        let inserted = try await database.execute("INSERT INTO test VALUES (1)", allowWrites: true)
        #expect(inserted.rowsAffected == "1")
        #expect(try await database.objects().map(\.name) == ["test"])
        let rows = try await database.execute(SQLiteDatabase.selectSQL(for: "test"))
        #expect(rows.rows[0][0].value == "1")
        #expect(SQLiteDatabase.selectSQL(for: "a\"b") == "SELECT * FROM \"a\"\"b\"")
    }
}

@Test func refusesBatchesBeforeFirstStatementExecutes() async throws {
    try await withDatabase { database, _ in
        _ = try await database.execute("CREATE TABLE test(value)", allowWrites: true)
        await #expect(throws: DatabaseError.multipleStatements) {
            try await database.execute("INSERT INTO test VALUES (1); INSERT INTO test VALUES (2)", allowWrites: true)
        }
        let result = try await database.execute("SELECT count(*) FROM test")
        #expect(result.rows[0][0].value == "0")
        do {
            _ = try await database.execute("PRAGMA user_version=7; SELECT 1", allowWrites: true)
            Issue.record("Prepare-time PRAGMA mutation was accepted")
        } catch { }
        #expect(try await database.execute("PRAGMA user_version").rows[0][0].value == "0")
    }
}

@Test func rowAndByteLimitsAreExplicit() async throws {
    try await withDatabase { database, _ in
        let truncated = try await database.execute("VALUES (1),(2),(3)", limits: QueryLimits(maxRows: 2))
        #expect(truncated.rows.count == 2 && truncated.truncated)
        let exact = try await database.execute("VALUES (1),(2)", limits: QueryLimits(maxRows: 2))
        #expect(exact.rows.count == 2 && !exact.truncated)
        await #expect(throws: DatabaseError.resultTooLarge) {
            try await database.execute("SELECT '12345'", limits: QueryLimits(maxCellBytes: 4))
        }
        await #expect(throws: DatabaseError.resultTooLarge) {
            try await database.execute("SELECT '12345'", limits: QueryLimits(maxResultBytes: 10))
        }
        await #expect(throws: DatabaseError.invalidLimits) {
            try await database.execute("SELECT 1", limits: QueryLimits(maxRows: 0))
        }
        await #expect(throws: DatabaseError.invalidText) {
            try await database.execute("SELECT CAST(x'FF' AS TEXT)")
        }
    }
}

@Test func busyFilesFailWithinBoundedTimeAndRecover() async throws {
    try await withDatabase { database, url in
        _ = try await database.execute("CREATE TABLE test(value)", allowWrites: true)
        _ = try await database.execute("BEGIN EXCLUSIVE", allowWrites: true)
        let other = SQLiteDatabase()
        try await other.open(url)
        let start = ProcessInfo.processInfo.systemUptime
        await #expect(throws: DatabaseError.busy) { try await other.execute("SELECT * FROM test") }
        #expect(ProcessInfo.processInfo.systemUptime - start < 2)
        _ = try await database.execute("ROLLBACK", allowWrites: true)
        #expect(try await other.execute("SELECT * FROM test").rows.isEmpty)
        await other.close()
    }
}

private let longQuery = "WITH RECURSIVE x(n) AS (VALUES(1) UNION ALL SELECT n+1 FROM x) SELECT sum(n) FROM x"

@Test func deadlineAndTaskCancellationLeaveConnectionUsable() async throws {
    try await withDatabase { database, _ in
        await #expect(throws: DatabaseError.canceled) {
            try await database.execute(longQuery, limits: QueryLimits(timeout: 0.02))
        }
        let query = Task { try await database.execute(longQuery) }
        try await Task.sleep(for: .milliseconds(20))
        query.cancel()
        await #expect(throws: DatabaseError.canceled) { try await query.value }
        #expect(try await database.execute("SELECT 1").rows[0][0].value == "1")
    }
}

@Test func reopenAndErrorsDoNotExposeFilePathsOrSQL() async throws {
    try await withDatabase { database, url in
        _ = try await database.execute("CREATE TABLE persisted(value)", allowWrites: true)
        await database.close()
        await #expect(throws: DatabaseError.notOpen) { try await database.execute("SELECT 1") }
        try await database.open(url)
        #expect(try await database.objects().map(\.name) == ["persisted"])
        do {
            _ = try await database.execute("synthetic_secret_invalid_sql")
            Issue.record("Invalid SQL was accepted")
        } catch {
            #expect(!error.localizedDescription.contains("synthetic_secret"))
            #expect(!error.localizedDescription.contains(url.path))
        }
    }
}
