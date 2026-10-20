// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import NIOCore
import PostgresNIO
import Testing
@testable import DBManagerCore

@Test func postgresSettingsRequireVerifiedTLSAndBoundedInputs() throws {
    let valid = PostgresSettings(host: "localhost", database: "synthetic", username: "synthetic", password: "public-fixture")
    let config = try valid.configuration(timeout: 10)
    #expect(config.tls.isEnforced && config.options.tlsServerName == "localhost")
    #expect(config.tls.sslContext?.configuration.certificateVerification == .fullVerification)
    #expect(throws: DatabaseError.invalidConnection) {
        try PostgresSettings(host: "host/path", database: "x", username: "x", password: "").configuration(timeout: 1)
    }
    #expect(throws: DatabaseError.invalidConnection) {
        try PostgresSettings(host: "localhost", database: "x", username: "x", password: "", certificateAuthority: Data("not a CA".utf8)).configuration(timeout: 1)
    }
}

@Test func postgresWireValuesPreservePrecisionAndRejectMalformedNumbers() throws {
    var numeric = ByteBuffer()
    // 12345678901234567890.12345678901234567890 (40 significant digits).
    for value: Int16 in [10,4,0,20,1234,5678,9012,3456,7890,1234,5678,9012,3456,7890] { numeric.writeInteger(value) }
    #expect(try PostgresValues.numeric(numeric, maxBytes: 1024) == "12345678901234567890.12345678901234567890")
    var zero = ByteBuffer(); for value: Int16 in [0,0,0,20] { zero.writeInteger(value) }
    #expect(try PostgresValues.numeric(zero, maxBytes: 1024) == "0.00000000000000000000")
    var invalid = ByteBuffer(); for value: Int16 in [1,0,0,0,10000] { invalid.writeInteger(value) }
    #expect(throws: DatabaseError.postgresFailed) { try PostgresValues.numeric(invalid, maxBytes: 1024) }
    var enormous = ByteBuffer(); for value: Int16 in [1,32767,0,0,1] { enormous.writeInteger(value) }
    #expect(throws: DatabaseError.resultTooLarge) { try PostgresValues.numeric(enormous, maxBytes: 1024) }
    #expect(PostgresValues.timestamp(123456, zoned: true) == "2000-01-01T00:00:00.123456Z")
    #expect(PostgresValues.timestamp(-1, zoned: false) == "1999-12-31T23:59:59.999999")
    #expect(PostgresValues.timestamp(.min, zoned: true) == "-infinity")
    let null = PostgresCell(bytes: nil, dataType: .bytea, format: .binary, columnName: "x", columnIndex: 0)
    let empty = PostgresCell(bytes: ByteBuffer(), dataType: .bytea, format: .binary, columnName: "x", columnIndex: 0)
    #expect(try PostgresValues.cell(null, maxBytes: 1024) == Cell(kind: .null))
    #expect(try PostgresValues.cell(empty, maxBytes: 1024) == Cell(kind: .binary, value: ""))
}

func liveSettings(host: String = "localhost", portVariable: String = "DBM_A2_TLS_PORT", roots: Bool = true) throws -> PostgresSettings? {
    let env = ProcessInfo.processInfo.environment
    guard let port = env[portVariable].flatMap(Int.init), let path = env["DBM_A2_CA_FILE"] else { return nil }
    return PostgresSettings(host: host, port: port, database: "probe", username: "native_app", password: "public-a2-fixture",
                            certificateAuthority: roots ? try Data(contentsOf: URL(fileURLWithPath: path)) : nil)
}

@Suite(.serialized) struct LivePostgresTests {
@Test(.enabled(if: ProcessInfo.processInfo.environment["DBM_A2_TLS_PORT"] != nil)) func livePostgresVerifiedTLSPrecisionAndReadOnly() async throws {
    guard let settings = try liveSettings() else { return }
    let database = PostgresDatabase()
    let objects = try await database.open(settings)
    #expect(objects.contains { $0.schema == "public" && $0.name == "synthetic_values" })
    let result = try await database.execute("SELECT * FROM public.synthetic_values")
    #expect(result.rows.count == 1)
    let row = result.rows[0]
    #expect(row[0] == Cell(kind: .decimal, value: "12345678901234567890.12345678901234567890"))
    #expect(row[1] == Cell(kind: .integer, value: "9223372036854775807"))
    #expect(row[2] == Cell(kind: .null))
    #expect(row[3] == Cell(kind: .text, value: ""))
    #expect(row[4] == Cell(kind: .binary, value: ""))
    #expect(row[5] == Cell(kind: .binary, value: "AP+A"))
    #expect(row[6] == Cell(kind: .boolean, value: "true"))
    #expect(row[7] == Cell(kind: .timestamp, value: "2026-10-20T12:34:56.123456Z"))
    #expect(row[8] == Cell(kind: .timestamp, value: "2026-10-20T12:34:56.654321"))
    #expect(row[9] == Cell(kind: .timestamp, value: "2026-10-20"))
    let empty = try await database.execute("SELECT amount FROM synthetic_values WHERE false")
    #expect(empty.rows.isEmpty && empty.columns.count == 1)
    for sql in ["INSERT INTO writable VALUES(1)", "WITH mutation AS (INSERT INTO writable VALUES(1) RETURNING value) SELECT * FROM mutation", "SET TRANSACTION READ WRITE", "SELECT set_config('transaction_read_only','off',true)", "SELECT mutating_function()"] {
        await #expect(throws: DatabaseError.postgresFailed) { try await database.execute(sql) }
    }
    // Extended protocol rejects a batch before executing its first statement.
    await #expect(throws: DatabaseError.postgresFailed) {
        try await database.execute("INSERT INTO writable VALUES(99); SELECT 1", allowWrites: true)
    }
    let before = try await database.execute("SELECT count(*) FROM writable")
    #expect(before.rows[0][0].value == "0")
    _ = try await database.execute("INSERT INTO writable VALUES(7)", allowWrites: true)
    let after = try await database.execute("SELECT value FROM writable")
    #expect(after.rows[0][0].value == "7")
    _ = try await database.execute("DELETE FROM writable", allowWrites: true)
    let special = DatabaseObject(name: "odd\"table", kind: "table", schema: "odd\"schema")
    let selected = try await database.execute(PostgresDatabase.selectSQL(for: special))
    #expect(selected.rows[0][0].value == "kept")
    await #expect(throws: DatabaseError.postgresFailed) { try await database.execute("SELECT 'synthetic-sensitive-text'::integer") }
    await database.close()
    await #expect(throws: DatabaseError.notOpen) { try await database.execute("SELECT 1") }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["DBM_A2_TLS_PORT"] != nil)) func livePostgresRejectsUnknownCAWrongHostAndNoTLS() async throws {
    guard let valid = try liveSettings() else { return }
    let database = PostgresDatabase()
    _ = try await database.open(valid)
    for settings in [try liveSettings(roots: false), try liveSettings(host: "127.0.0.1"), try liveSettings(portVariable: "DBM_A2_WRONGHOST_PORT"), try liveSettings(portVariable: "DBM_A2_PLAIN_PORT")] {
        let settings = try #require(settings)
        await #expect(throws: DatabaseError.connectionFailed) { try await database.open(settings) }
        await #expect(throws: DatabaseError.notOpen) { try await database.execute("SELECT 1") }
    }
    let wrongPassword = PostgresSettings(host: valid.host, port: valid.port, database: valid.database, username: valid.username,
                                        password: "synthetic-wrong", certificateAuthority: valid.certificateAuthority)
    await #expect(throws: DatabaseError.connectionFailed) { try await database.open(wrongPassword) }
    _ = try await database.open(valid)
    await database.close()
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["DBM_A2_TLS_PORT"] != nil)) func livePostgresLimitsCancellationAndPhysicalRelease() async throws {
    guard let settings = try liveSettings() else { return }
    let database = PostgresDatabase()
    _ = try await database.open(settings)
    let truncated = try await database.execute("SELECT i FROM generate_series(1,10000000) i", limits: QueryLimits(maxRows: 2))
    #expect(truncated.rows.count == 2 && truncated.truncated)
    await #expect(throws: DatabaseError.resultTooLarge) { try await database.execute("SELECT repeat('x',1048577)") }
    await #expect(throws: DatabaseError.resultTooLarge) {
        try await database.execute("SELECT repeat(chr(1),1000) FROM generate_series(1,10)", limits: QueryLimits(maxResultBytes: 8000))
    }
    await #expect(throws: DatabaseError.canceled) { try await database.execute("SELECT pg_sleep(10)", limits: QueryLimits(timeout: 0.15)) }
    let task = Task { try await database.execute("SELECT pg_sleep(20)") }
    let monitor = PostgresDatabase()
    _ = try await monitor.open(settings)
    var observedRunning = false
    for _ in 0..<50 {
        let state = try await monitor.execute("SELECT count(*) FROM pg_stat_activity WHERE application_name LIKE 'DBManagerApple:%' AND state='active' AND query='SELECT pg_sleep(20)'")
        if state.rows[0][0].value == "1" { observedRunning = true; break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(observedRunning)
    await monitor.close()
    let unrelated = PostgresDatabase()
    _ = try await unrelated.open(settings)
    let unrelatedQuery = Task { try await unrelated.execute("SELECT pg_sleep(0.3),77") }
    task.cancel()
    await #expect(throws: DatabaseError.canceled) { try await task.value }
    let unrelatedResult = try await unrelatedQuery.value
    #expect(unrelatedResult.rows[0][1].value == "77")
    await unrelated.close()
    // A fresh backend checks the old physical query/session is gone, not only its Swift task.
    var released = false
    for _ in 0..<50 {
        let state = try await database.execute("SELECT count(*) FROM pg_stat_activity WHERE application_name LIKE 'DBManagerApple:%' AND pid<>pg_backend_pid()")
        if state.rows[0][0].value == "0" { released = true; break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(released)
    let result = try await database.execute("SELECT 42")
    #expect(result.rows[0][0].value == "42")
    let closing = Task { try await database.execute("SELECT pg_sleep(10)") }
    try await Task.sleep(for: .milliseconds(150))
    await database.close()
    await #expect(throws: DatabaseError.canceled) { try await closing.value }
    await #expect(throws: DatabaseError.notOpen) { try await database.execute("SELECT 1") }
    _ = try await database.open(settings)
    await database.close()
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["DBM_A2_TLS_PORT"] != nil))
func livePostgresReportsUnconfirmedCancellation() async throws {
    guard let settings = try liveSettings() else { return }
    let database = PostgresDatabase()
    _ = try await database.open(settings)
    // User SQL can change session parameters; do not signal a PID without all ownership anchors.
    let task = Task { try await database.execute("SELECT set_config('application_name','synthetic-a2-changed',true),pg_sleep(0.6)") }
    try await Task.sleep(for: .milliseconds(150))
    task.cancel()
    await #expect(throws: DatabaseError.cancellationUnconfirmed) { try await task.value }
    try await Task.sleep(for: .milliseconds(700))
    let reused = try await database.execute("SELECT 1")
    #expect(reused.rows[0][0].value == "1")
    await database.close()
}

}

@Test func originalNoticesAreIncludedInRuntimeResources() {
    let text = ThirdPartyNotices.text
    #expect(text.contains("GNU AFFERO GENERAL PUBLIC LICENSE"))
    #expect(text.contains("15e0b9e495786807272dd4891fa4bac76aa43034"))
    #expect(text.contains("8eb25be6fa18d475291122887a7bccd3762ff236"))
    #expect(text.contains("PostgresNIO") || text.contains("postgres-nio"))
}
