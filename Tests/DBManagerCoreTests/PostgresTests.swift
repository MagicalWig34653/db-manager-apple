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

@Test(.enabled(if: ProcessInfo.processInfo.environment["DBM_A2_TLS_PORT"] != nil))
func livePostgresHistoricalCalendarAndEraMatchServer() async throws {
    guard let settings = try liveSettings() else { return }
    let database = PostgresDatabase()
    _ = try await database.open(settings)
    let dateLiterals = ["4713-01-01 BC", "0002-12-31 BC", "0001-01-01 BC", "0001-02-29 BC", "0001-12-31 BC", "0001-01-01 AD", "1500-01-01", "1500-03-01", "1582-10-04", "1582-10-05", "1600-02-29", "1700-03-01", "1900-03-01", "2000-02-29", "5874897-12-31", "-infinity", "infinity"]
    let dates = dateLiterals.map { "(DATE '\($0)')" }.joined(separator: ",")
    let result = try await database.execute("SELECT d,d::text FROM (VALUES " + dates + ") fixture(d)")
    #expect(result.rows.count == dateLiterals.count)
    for row in result.rows { #expect(row[0].kind == .timestamp && row[0].value == row[1].value) }
    let timestamps = ["4713-01-01 00:00:00.000001 BC", "0001-01-01 00:00:00.123456 BC", "0001-12-31 23:59:59.999999 BC", "0001-01-01 00:00:00.000000 AD", "1500-01-01 12:34:56.123456", "1582-10-04 23:59:59.999999", "1582-10-05 00:00:00.000001", "1600-02-29 12:00:00.123456", "1999-12-31 23:59:59.999999", "2000-02-29 12:34:56.654321", "294276-12-31 23:59:59.999999", "-infinity", "infinity"]
    for zoned in [false,true] {
        let type = zoned ? "timestamptz" : "timestamp"
        let values = timestamps.map { original -> String in
            var value = original
            if zoned && !value.contains("infinity") {
                if value.hasSuffix(" BC") { value = String(value.dropLast(3)) + "+00 BC" }
                else if value.hasSuffix(" AD") { value = String(value.dropLast(3)) + "+00 AD" }
                else { value += "+00" }
            }
            return "(\(type) '\(value)')"
        }.joined(separator: ",")
        let civil = zoned ? "t AT TIME ZONE 'UTC'" : "t"
        let suffix = zoned ? "Z" : ""
        let sql = "SELECT t,CASE WHEN t IN ('-infinity','infinity') THEN t::text ELSE to_char(" + civil + ", 'YYYY-MM-DD\"T\"HH24:MI:SS.US') || '" + suffix + "' || CASE WHEN extract(year FROM " + civil + ")<0 THEN ' BC' ELSE '' END END FROM (VALUES " + values + ") fixture(t)"
        let result = try await database.execute(sql)
        #expect(result.rows.count == timestamps.count)
        for row in result.rows { #expect(row[0].kind == .timestamp && row[0].value == row[1].value) }
    }
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

@Test func historicalPostgresCalendarsPreserveGregorianDateAndEra() throws {
    #expect(PostgresValues.timestamp(-15_778_454_400_000_000, zoned: false) == "1500-01-01T00:00:00.000000")
    #expect(PostgresValues.timestamp(-63_082_281_600_000_000, zoned: true) == "0001-01-01T00:00:00.000000Z")
    #expect(PostgresValues.timestamp(-63_113_904_000_000_000, zoned: false) == "0001-01-01T00:00:00.000000 BC")
    for (microseconds, expected) in [(Int64(-15_778_454_400_000_000), "1500-01-01"), (Int64(-63_082_281_600_000_000), "0001-01-01"), (Int64(-63_113_904_000_000_000), "0001-01-01 BC")] {
        var bytes = ByteBuffer(); bytes.writeInteger(Int32(microseconds / 86_400_000_000))
        let source = PostgresCell(bytes: bytes, dataType: .date, format: .binary, columnName: "historical", columnIndex: 0)
        #expect(try PostgresValues.cell(source, maxBytes: 1024).value == expected)
    }
}

@Test func postgresGregorianLeapDaysNegativeRemaindersAndInfinity() {
    #expect(PostgresValues.date(-730119) == "0001-01-01")
    #expect(PostgresValues.date(-182563) == "1500-02-28")
    #expect(PostgresValues.date(-182562) == "1500-03-01")
    #expect(PostgresValues.date(-152395) == "1582-10-04")
    #expect(PostgresValues.date(-152394) == "1582-10-05")
    #expect(PostgresValues.date(-146038) == "1600-02-29")
    #expect(PostgresValues.date(-109513) == "1700-03-01")
    #expect(PostgresValues.date(-36465) == "1900-03-01")
    #expect(PostgresValues.date(59) == "2000-02-29")
    #expect(PostgresValues.date(60) == "2000-03-01")
    #expect(PostgresValues.date(2921939) == "9999-12-31")
    #expect(PostgresValues.date(-730_426) == "0001-02-29 BC")
    #expect(PostgresValues.timestamp(-63_082_281_600_000_001, zoned: false) == "0001-12-31T23:59:59.999999 BC")
    #expect(PostgresValues.timestamp(-1, zoned: true) == "1999-12-31T23:59:59.999999Z")
    #expect(PostgresValues.date(.min) == "-infinity")
    #expect(PostgresValues.date(.max) == "infinity")
    #expect(PostgresValues.timestamp(.min, zoned: false) == "-infinity")
    #expect(PostgresValues.timestamp(.max, zoned: true) == "infinity")
    #expect(PostgresValues.timestamp(.min + 1, zoned: false).hasSuffix(".224193 BC"))
    #expect(PostgresValues.timestamp(.max - 1, zoned: true).hasSuffix(".775806Z"))
}
