// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import NIOCore
import NIOEmbedded
import NIOSSL
import Security
import Testing
@testable import DBManagerCore

private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

@Test func mysqlSettingsRequireVerifiedTLSByDefaultAndBoundedInputs() throws {
    let valid = MySQLSettings(host: "db.example.test", username: "synthetic", password: "public-fixture")
    #expect(valid.transportSecurity == .verifiedTLS)
    let config = try valid.configuration(timeout: 10)
    #expect(config.tls?.configuration.certificateVerification == .fullVerification)
    #expect(config.tls?.configuration.minimumTLSVersion == .tlsv12)
    #expect(throws: DatabaseError.invalidMySQLConnection) {
        try MySQLSettings(host: "host/path", username: "x", password: "").configuration(timeout: 1)
    }
    #expect(throws: DatabaseError.invalidMySQLConnection) {
        try MySQLSettings(host: "localhost", username: "x", password: "", certificateAuthority: Data("not a CA".utf8)).configuration(timeout: 1)
    }
    #expect(throws: DatabaseError.invalidMySQLConnection) {
        try MySQLSettings(host: "localhost", username: "", password: "").configuration(timeout: 1)
    }
}

@Test func mysqlTransportModesAreExplicitAndExposeTheirWarningLevel() throws {
    #expect(MySQLTransportSecurity.allCases.count == 3)
    #expect(MySQLTransportSecurity.verifiedTLS.warning == .none && MySQLTransportSecurity.verifiedTLS.verifiesServerIdentity)
    #expect(MySQLTransportSecurity.unverifiedTLS.warning == .serverIdentityUnverified && MySQLTransportSecurity.unverifiedTLS.usesTLS)
    #expect(!MySQLTransportSecurity.unverifiedTLS.verifiesServerIdentity)
    #expect(MySQLTransportSecurity.plaintext.warning == .noEncryption && !MySQLTransportSecurity.plaintext.usesTLS)
    #expect(MySQLSecurityWarning.none < .serverIdentityUnverified && MySQLSecurityWarning.serverIdentityUnverified < .noEncryption)
    // Positive: every mode is accepted for ordinary (non-loopback) hosts when chosen explicitly.
    let verified = try MySQLSettings(host: "db.example.test", username: "x", password: "").configuration(timeout: 1)
    #expect(verified.tls?.configuration.certificateVerification == .fullVerification && verified.serverName == "db.example.test")
    let unverified = try MySQLSettings(host: "db.example.test", username: "x", password: "", transportSecurity: .unverifiedTLS).configuration(timeout: 1)
    #expect(unverified.tls?.configuration.certificateVerification == CertificateVerification.none && unverified.serverName == nil)
    #expect(unverified.tls?.configuration.minimumTLSVersion == .tlsv12)
    let plain = try MySQLSettings(host: "10.0.0.5", username: "x", password: "", transportSecurity: .plaintext).configuration(timeout: 1)
    #expect(plain.tls == nil && plain.security == .plaintext)
    // Negative: modes that do not verify refuse a CA file instead of silently ignoring it.
    for mode in [MySQLTransportSecurity.unverifiedTLS, .plaintext] {
        #expect(throws: DatabaseError.invalidMySQLConnection) {
            try MySQLSettings(host: "localhost", username: "x", password: "", certificateAuthority: Data("x".utf8), transportSecurity: mode).configuration(timeout: 1)
        }
    }
    // The default of the initializer is the verified mode.
    #expect(MySQLSettings(host: "h", username: "u", password: "p").transportSecurity == .verifiedTLS)
}

@Test func mysqlAuthScramblesMatchReferenceVectors() {
    let password = Array("public-a4-fixture".utf8)
    let scramble = Array(1...20 as ClosedRange<UInt8>)
    // Vectors computed independently with Python hashlib from the documented algorithms.
    #expect(hex(MySQLAuth.nativePassword(password: password, scramble: scramble)) == "4b7523acb6589d6116577935edb8ea08fa2b65fd")
    #expect(hex(MySQLAuth.cachingSHA2(password: password, scramble: scramble)) == "4ec8df7adc94564138b8d64378455548eebf9863a1b5d21955135dbd86ebaee1")
    #expect(MySQLAuth.nativePassword(password: [], scramble: scramble).isEmpty)
    #expect(MySQLAuth.response(plugin: "sha256_password", password: password, scramble: scramble) == nil)
    #expect(MySQLAuth.response(plugin: "client_ed25519", password: password, scramble: scramble) == nil)
}

@Test func mysqlLengthEncodedIntegersRoundTripAndRejectMalformedInput() {
    for value: UInt64 in [0, 250, 251, 65_535, 65_536, 16_777_215, 16_777_216, .max] {
        var buffer = ByteBuffer(); buffer.writeMySQLLengthEncodedInteger(value)
        #expect(buffer.readMySQLLengthEncodedInteger() == value && buffer.readableBytes == 0)
    }
    var null = ByteBuffer(bytes: [0xFB]); #expect(null.readMySQLLengthEncodedInteger() == nil)
    var reserved = ByteBuffer(bytes: [0xFF]); #expect(reserved.readMySQLLengthEncodedInteger() == nil)
    var truncated = ByteBuffer(bytes: [0xFC, 0x01]); #expect(truncated.readMySQLLengthEncodedInteger() == nil)
    var oversize = ByteBuffer(bytes: [0x05, 1, 2])
    #expect(throws: DatabaseError.mysqlProtocolError) { try oversize.readMySQLLengthEncodedBytes(maxLength: 10) }
    var limit = ByteBuffer(bytes: [0x03, 1, 2, 3])
    #expect(throws: DatabaseError.resultTooLarge) { try limit.readMySQLLengthEncodedBytes(maxLength: 2) }
}

@Test func mysqlPacketAssemblerEnforcesSequenceAndLimits() throws {
    var assembler = MySQLPacketAssembler()
    var sequence: UInt8 = 0
    let one = try MySQLPacketAssembler.frame([1, 2, 3], sequence: &sequence)
    var second = try MySQLPacketAssembler.frame([4], sequence: &sequence)
    var joined = one; joined.writeBuffer(&second)
    // Fed in 1-byte steps to exercise partial reads.
    var collected: [[UInt8]] = []
    for byte in joined.readableBytesView {
        assembler.append(ByteBuffer(bytes: [byte]))
        while let payload = try assembler.nextPayload(maxPayload: 100) { collected.append(Array(payload.readableBytesView)) }
    }
    #expect(collected == [[1, 2, 3], [4]])
    var wrong = MySQLPacketAssembler()
    var badSequence: UInt8 = 5
    wrong.append(try MySQLPacketAssembler.frame([1], sequence: &badSequence))
    #expect(throws: DatabaseError.mysqlProtocolError) { try wrong.nextPayload(maxPayload: 100) }
    var small = MySQLPacketAssembler()
    var zero: UInt8 = 0
    small.append(try MySQLPacketAssembler.frame(Array(repeating: 0, count: 50), sequence: &zero))
    #expect(throws: DatabaseError.resultTooLarge) { try small.nextPayload(maxPayload: 10) }
}

@Test func mysqlGreetingParsingRejectsTruncatedInput() throws {
    var buffer = ByteBuffer()
    buffer.writeInteger(10 as UInt8)
    buffer.writeString("11.4.4-MariaDB"); buffer.writeInteger(0 as UInt8)
    buffer.writeInteger(77 as UInt32, endianness: .little)
    buffer.writeBytes(Array(1...8 as ClosedRange<UInt8>)); buffer.writeInteger(0 as UInt8)
    let capabilities = MySQLCapability.protocol41 | MySQLCapability.secureConnection | MySQLCapability.ssl | MySQLCapability.pluginAuth
    buffer.writeInteger(UInt16(capabilities & 0xFFFF), endianness: .little)
    buffer.writeInteger(45 as UInt8); buffer.writeInteger(2 as UInt16, endianness: .little)
    buffer.writeInteger(UInt16(capabilities >> 16), endianness: .little)
    buffer.writeInteger(21 as UInt8); buffer.writeRepeatingByte(0, count: 10)
    buffer.writeBytes(Array(9...20 as ClosedRange<UInt8>)); buffer.writeInteger(0 as UInt8)
    buffer.writeString("mysql_native_password"); buffer.writeInteger(0 as UInt8)
    let greeting = try MySQLGreeting.parse(buffer)
    #expect(greeting.isMariaDB && greeting.threadID == 77 && greeting.pluginName == "mysql_native_password")
    #expect(greeting.scramble == Array(1...20 as ClosedRange<UInt8>))
    #expect(greeting.capabilities & MySQLCapability.ssl != 0)
    for length in [0, 1, 5, 20, 30] {
        let cut = buffer.getSlice(at: 0, length: length)!
        #expect(throws: DatabaseError.self) { try MySQLGreeting.parse(cut) }
    }
}

private func column(_ type: UInt8, charset: UInt16 = 45, flags: UInt16 = 0) -> MySQLColumnDefinition {
    MySQLColumnDefinition(name: "c", characterSet: charset, type: type, flags: flags)
}

@Test func mysqlTextValuesStayExact() throws {
    func cell(_ text: String?, _ column: MySQLColumnDefinition) throws -> Cell {
        try MySQLValues.cell(text.map { Array($0.utf8) }, column: column, maxBytes: 1024)
    }
    #expect(try cell(nil, column(253)) == Cell(kind: .null))
    #expect(try cell("12345678901234567890.12345678901234567890", column(246)) == Cell(kind: .decimal, value: "12345678901234567890.12345678901234567890"))
    #expect(try cell("18446744073709551615", column(8, flags: 32)) == Cell(kind: .integer, value: "18446744073709551615"))
    #expect(try cell("2026-10-20 12:34:56.654321", column(12)) == Cell(kind: .timestamp, value: "2026-10-20T12:34:56.654321"))
    #expect(try cell("2026-10-20 12:34:56", column(7)) == Cell(kind: .timestamp, value: "2026-10-20T12:34:56Z"))
    #expect(try cell("2026-10-20", column(10)) == Cell(kind: .timestamp, value: "2026-10-20"))
    // Zero dates are not instants; they stay text instead of becoming a made-up timestamp.
    #expect(try cell("0000-00-00", column(10)) == Cell(kind: .text, value: "0000-00-00"))
    #expect(try cell("0000-00-00 00:00:00", column(12)) == Cell(kind: .text, value: "0000-00-00 00:00:00"))
    #expect(try cell("-12:34:56.789", column(11)) == Cell(kind: .text, value: "-12:34:56.789"))
    #expect(try cell("", column(252, charset: 63)) == Cell(kind: .binary, value: ""))
    #expect(try MySQLValues.cell([0, 0xFF, 0x80], column: column(252, charset: 63), maxBytes: 8) == Cell(kind: .binary, value: "AP+A"))
    #expect(try cell("Grüße", column(253)) == Cell(kind: .text, value: "Grüße"))
    #expect(throws: DatabaseError.invalidText) { try MySQLValues.cell([0xFF, 0xFE], column: column(253), maxBytes: 8) }
    #expect(throws: DatabaseError.resultTooLarge) { try MySQLValues.cell(Array(repeating: 65, count: 9), column: column(253), maxBytes: 8) }
}

@Test func mysqlPreTLSQueuedBytesAbortTheConnection() throws {
    // STARTTLS injection guard (review F1): data queued before TLS is attacker controlled.
    let channel = EmbeddedChannel()
    let handler = MySQLInboundHandler()
    try channel.pipeline.syncOperations.addHandler(handler)
    try handler.requireNoQueuedData()
    try channel.writeInbound(ByteBuffer(bytes: [7, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0]))
    #expect(throws: DatabaseError.mysqlProtocolError) { try handler.requireNoQueuedData() }
    _ = try? channel.finish()
}

@Test func mysqlSettingsAndConfigRedactSecretsInReflection() throws {
    let settings = MySQLSettings(host: "db.example.test", database: "d", username: "user-secret-name", password: "hunter2-secret")
    let config = try settings.configuration(timeout: 1)
    for text in [String(describing: settings), String(reflecting: settings), String(describing: config), String(reflecting: config),
                 { var out = ""; dump(settings, to: &out); return out }(), { var out = ""; dump(config, to: &out); return out }()] {
        #expect(!text.contains("hunter2") && !text.contains("user-secret-name") && !text.contains("db.example.test"))
    }
}

@Test func mysqlFailureMappingKeepsOriginalCauseOfLimitAborts() {
    // Review F5: a failed follow-up KILL must not hide resultTooLarge / invalidText.
    #expect(MySQLDatabase.failure(DatabaseError.resultTooLarge, canceled: false, stopped: true, confirmed: false) == .resultTooLarge)
    #expect(MySQLDatabase.failure(DatabaseError.invalidText, canceled: false, stopped: true, confirmed: false) == .invalidText)
    // A user cancellation with unconfirmed KILL is still reported honestly.
    #expect(MySQLDatabase.failure(DatabaseError.resultTooLarge, canceled: true, stopped: true, confirmed: false) == .cancellationUnconfirmed)
    #expect(MySQLDatabase.failure(CancellationError(), canceled: true, stopped: true, confirmed: true) == .canceled)
    #expect(MySQLDatabase.failure(DatabaseError.mysqlFailed(1064), canceled: false, stopped: false, confirmed: true) == .mysqlFailed(1064))
    #expect(MySQLDatabase.failure(CancellationError(), canceled: false, stopped: false, confirmed: true) == .mysqlConnectionFailed)
}

// MARK: RSA key exchange for caching_sha2_password full authentication

private func derLength(_ n: Int) -> [UInt8] { n < 128 ? [UInt8(n)] : n < 256 ? [0x81, UInt8(n)] : [0x82, UInt8(n >> 8), UInt8(n & 0xFF)] }
private func der(_ tag: UInt8, _ body: [UInt8]) -> [UInt8] { [tag] + derLength(body.count) + body }
private func pem(_ label: String, _ der: [UInt8]) -> [UInt8] {
    Array("-----BEGIN \(label)-----\n\(Data(der).base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed]))\n-----END \(label)-----\n".utf8)
}
private func spkiPEM(pkcs1: [UInt8]) -> [UInt8] {
    let algorithm = der(0x30, der(0x06, [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]) + [0x05, 0x00])
    return pem("PUBLIC KEY", der(0x30, algorithm + der(0x03, [0] + pkcs1)))
}
private func rsaKey(bits: Int) throws -> (priv: SecKey, pkcs1: [UInt8]) {
    let attrs: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: bits]
    let priv = try #require(SecKeyCreateRandomKey(attrs as CFDictionary, nil))
    let pub = try #require(SecKeyCopyPublicKey(priv))
    return (priv, Array(try #require(SecKeyCopyExternalRepresentation(pub, nil)) as Data))
}

@Test func mysqlRSAPasswordEncryptionRoundTripsAndNeverContainsClearPassword() throws {
    let key = try rsaKey(bits: 2048)
    let nonce = Array(1...20 as ClosedRange<UInt8>)
    let password = Array("public-a4-fixture".utf8)
    for encoded in [spkiPEM(pkcs1: key.pkcs1), pem("RSA PUBLIC KEY", key.pkcs1)] {
        let cipher = try MySQLRSA.encryptPassword(password: password, nonce: nonce, publicKeyPEM: encoded)
        #expect(cipher.count == 256 && !Data(cipher).contains(Data(password)))
        let plain = try #require(SecKeyCreateDecryptedData(key.priv, .rsaEncryptionOAEPSHA1, Data(cipher) as CFData, nil)) as Data
        #expect(Array(plain) == MySQLRSA.xorWithNonce(password: password, nonce: nonce))
        // Receiver side: XOR again and strip the NUL gives back the password.
        let restored = Array(plain).enumerated().map { $0.element ^ nonce[$0.offset % nonce.count] }
        #expect(restored == password + [0])
    }
    // Empty password still produces a valid message (single NUL).
    #expect(try MySQLRSA.encryptPassword(password: [], nonce: nonce, publicKeyPEM: spkiPEM(pkcs1: key.pkcs1)).count == 256)
}

@Test func mysqlRSARejectsBrokenSmallOrOversizedKeysAndMessages() throws {
    let good = try rsaKey(bits: 2048)
    let nonce = Array(1...20 as ClosedRange<UInt8>)
    func encrypt(_ pem: [UInt8], password: [UInt8] = [1]) throws -> [UInt8] { try MySQLRSA.encryptPassword(password: password, nonce: nonce, publicKeyPEM: pem) }
    // Too small key (1024 bits).
    let small = try rsaKey(bits: 1024)
    #expect(throws: DatabaseError.mysqlUnsupportedAuth) { try encrypt(spkiPEM(pkcs1: small.pkcs1)) }
    // Garbage, truncated, wrong labels, wrong algorithm OID, trailing data.
    #expect(throws: DatabaseError.mysqlProtocolError) { try encrypt(Array("not a key".utf8)) }
    #expect(throws: DatabaseError.mysqlProtocolError) { try encrypt([]) }
    let valid = spkiPEM(pkcs1: good.pkcs1)
    #expect(throws: DatabaseError.mysqlProtocolError) { try encrypt(Array(valid.prefix(valid.count / 2))) }
    #expect(throws: DatabaseError.mysqlProtocolError) { try encrypt(pem("CERTIFICATE", good.pkcs1)) }
    #expect(throws: DatabaseError.mysqlProtocolError) { try encrypt(pem("PUBLIC KEY", der(0x30, der(0x30, der(0x06, [0x2A, 0x03]) + [0x05, 0x00]) + der(0x03, [0] + good.pkcs1)))) }
    #expect(throws: DatabaseError.mysqlProtocolError) { try encrypt(pem("RSA PUBLIC KEY", good.pkcs1 + [0])) }
    // Even modulus, tiny exponent, huge length claims.
    let evenModulus = der(0x30, der(0x02, [0] + Array(repeating: 0xFE, count: 256)) + der(0x02, [1, 0, 1]))
    #expect(throws: DatabaseError.mysqlProtocolError) { try encrypt(pem("RSA PUBLIC KEY", evenModulus)) }
    #expect(throws: DatabaseError.mysqlProtocolError) { try encrypt(pem("RSA PUBLIC KEY", [0x30, 0x82, 0xFF, 0xFF, 0x02])) }
    #expect(throws: DatabaseError.mysqlProtocolError) { try encrypt(Array(repeating: 0x41, count: 5000)) }
    let e3 = der(0x30, der(0x02, [0] + Array(repeating: 0xFF, count: 256)) + der(0x02, [3]))
    #expect(throws: DatabaseError.mysqlUnsupportedAuth) { try encrypt(pem("RSA PUBLIC KEY", e3)) }
    // Password too long for the key (OAEP-SHA1 capacity is 256 - 42 bytes).
    #expect(throws: DatabaseError.mysqlUnsupportedAuth) { try encrypt(valid, password: Array(repeating: 65, count: 215)) }
    #expect(throws: Never.self) { _ = try encrypt(valid, password: Array(repeating: 65, count: 213)) }
    #expect(throws: DatabaseError.mysqlProtocolError) { try MySQLRSA.encryptPassword(password: [1], nonce: [], publicKeyPEM: valid) }
}

// MARK: Live tests against disposable fixtures (scripts/test-mysql.py)

private let liveEnabled = ProcessInfo.processInfo.environment["DBM_A4_MARIA_TLS_PORT"] != nil

private func mysqlLiveSettings(_ port: String = "DBM_A4_MARIA_TLS_PORT", host: String = "localhost", roots: String? = "DBM_A4_CA_FILE",
                          password: String = "public-a4-fixture", security: MySQLTransportSecurity = .verifiedTLS) throws -> MySQLSettings? {
    let env = ProcessInfo.processInfo.environment
    guard let value = env[port].flatMap(Int.init) else { return nil }
    let ca = try roots.flatMap { env[$0] }.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
    return MySQLSettings(host: host, port: value, database: "probe", username: "native_app", password: password,
                         certificateAuthority: ca, transportSecurity: security)
}

@Suite(.serialized) struct LiveMySQLTests {
    @Test(.enabled(if: liveEnabled), arguments: ["DBM_A4_MARIA_TLS_PORT", "DBM_A4_MYSQL_TLS_PORT"])
    func liveVerifiedTLSPrecisionCatalogAndReadOnly(portVariable: String) async throws {
        let settings = try #require(try mysqlLiveSettings(portVariable))
        let database = MySQLDatabase()
        let objects = try await database.open(settings)
        #expect(objects.contains { $0.schema == "probe" && $0.name == "synthetic_values" && $0.kind == "table" })
        #expect(objects.contains { $0.schema == "probe" && $0.name == "synthetic_view" && $0.kind == "view" })
        #expect(!objects.contains { $0.schema == "mysql" || $0.schema == "information_schema" })
        let result = try await database.execute("SELECT * FROM probe.synthetic_values")
        #expect(result.rows.count == 1)
        let row = result.rows[0]
        #expect(row[0] == Cell(kind: .decimal, value: "12345678901234567890.12345678901234567890"))
        #expect(row[1] == Cell(kind: .integer, value: "18446744073709551615"))
        #expect(row[2] == Cell(kind: .null))
        #expect(row[3] == Cell(kind: .text, value: ""))
        #expect(row[4] == Cell(kind: .binary, value: ""))
        #expect(row[5] == Cell(kind: .binary, value: "AP+A"))
        #expect(row[6] == Cell(kind: .integer, value: "1"))
        #expect(row[7] == Cell(kind: .timestamp, value: "2026-10-20T12:34:56.123456Z"))
        #expect(row[8] == Cell(kind: .timestamp, value: "2026-10-20T12:34:56.654321"))
        #expect(row[9] == Cell(kind: .timestamp, value: "2026-10-20"))
        #expect(row[10] == Cell(kind: .text, value: "-12:34:56.789"))
        #expect(row[11] == Cell(kind: .float, value: "1.5"))
        #expect(row[12] == Cell(kind: .text, value: "Grüße \u{1F600}"))
        #expect(result.columns[0].databaseType == "DECIMAL" && result.columns[1].databaseType == "BIGINT UNSIGNED")
        let empty = try await database.execute("SELECT amount FROM probe.synthetic_values WHERE false")
        #expect(empty.rows.isEmpty && empty.columns.count == 1)
        // Read-only mode: statements, mutating functions and SET TRANSACTION all fail.
        for sql in ["INSERT INTO probe.writable VALUES(1)", "SELECT probe.mutating_function()", "SET TRANSACTION READ WRITE",
                    "CREATE TABLE probe.sneaky(a INT)"] {
            await #expect(throws: DatabaseError.self) { try await database.execute(sql) }
        }
        // Multi-statement text is a protocol error without CLIENT_MULTI_STATEMENTS.
        await #expect(throws: DatabaseError.self) { try await database.execute("INSERT INTO probe.writable VALUES(99); SELECT 1", allowWrites: true) }
        #expect(try await database.execute("SELECT count(*) FROM probe.writable").rows[0][0].value == "0")
        let written = try await database.execute("INSERT INTO probe.writable VALUES(7)", allowWrites: true)
        #expect(written.rowsAffected == "1" && written.columns.isEmpty)
        #expect(try await database.execute("SELECT value FROM probe.writable").rows[0][0].value == "7")
        _ = try await database.execute("DELETE FROM probe.writable", allowWrites: true)
        // Identifier quoting for navigation, including backticks.
        let odd = try #require(objects.first { $0.schema == "odd`db" })
        #expect(try await database.execute(MySQLDatabase.selectSQL(for: odd)).rows[0][0].value == "kept")
        await database.close()
    }

    @Test(.enabled(if: liveEnabled)) func liveRejectsUnknownCAWrongHostAndServerWithoutTLS() async throws {
        let valid = try #require(try mysqlLiveSettings())
        let database = MySQLDatabase()
        _ = try await database.open(valid)
        let cases: [MySQLSettings?] = [
            try mysqlLiveSettings(roots: nil),                          // self-signed CA not in the system store
            try mysqlLiveSettings(roots: "DBM_A4_OTHER_CA_FILE"),       // unrelated CA
            try mysqlLiveSettings(host: "127.0.0.1"),                   // IP literal not in the certificate
            try mysqlLiveSettings("DBM_A4_MARIA_WRONGHOST_PORT"),       // certificate issued for another host
        ]
        for settings in cases {
            let settings = try #require(settings)
            await #expect(throws: DatabaseError.mysqlConnectionFailed) { try await database.open(settings) }
            await #expect(throws: DatabaseError.notOpen) { try await database.execute("SELECT 1") }
        }
        // Server without TLS: refused before any credential is sent, no downgrade.
        let plain = try #require(try mysqlLiveSettings("DBM_A4_MARIA_PLAIN_PORT"))
        await #expect(throws: DatabaseError.mysqlTLSRequired) { try await database.open(plain) }
        let wrongPassword = try #require(try mysqlLiveSettings(password: "synthetic-wrong"))
        await #expect(throws: DatabaseError.mysqlConnectionFailed) { try await database.open(wrongPassword) }
        _ = try await database.open(valid)
        await database.close()
    }

    @Test(.enabled(if: liveEnabled)) func liveExplicitTransportModes() async throws {
        func cipher(_ settings: MySQLSettings) async throws -> String {
            let database = MySQLDatabase()
            _ = try await database.open(settings)
            let value = try await database.execute("SHOW SESSION STATUS LIKE 'Ssl_cipher'").rows[0][1].value ?? "?"
            await database.close()
            return value
        }
        // (1) verified TLS: encrypted.
        #expect(try await cipher(try #require(try mysqlLiveSettings())).isEmpty == false)
        // (2) unverified TLS: encrypted, and works where verification fails (no CA, IP target, MySQL server).
        for (port, host) in [("DBM_A4_MARIA_TLS_PORT", "localhost"), ("DBM_A4_MARIA_TLS_PORT", "127.0.0.1"), ("DBM_A4_MYSQL_TLS_PORT", "localhost")] {
            let settings = try #require(try mysqlLiveSettings(port, host: host, roots: nil, security: .unverifiedTLS))
            #expect(try await cipher(settings).isEmpty == false)
        }
        // The wrong-host fixture has no accounts: the unverified mode gets past the certificate and fails at login.
        let wrongHostUnverified = try #require(try mysqlLiveSettings("DBM_A4_MARIA_WRONGHOST_PORT", roots: nil, security: .unverifiedTLS))
        await #expect(throws: DatabaseError.mysqlConnectionFailed) { try await MySQLDatabase().open(wrongHostUnverified) }
        // (3) plaintext: works on a server without TLS (any host by design), session is unencrypted.
        let plain = try #require(try mysqlLiveSettings("DBM_A4_MARIA_PLAIN_PORT", roots: nil, security: .plaintext))
        #expect(try await cipher(plain).isEmpty)
        // A caching_sha2 account that never authenticated needs full authentication: inside TLS (verified or not)
        // the clear password goes through the TLS session; without TLS it is sent RSA-OAEP encrypted
        // (public key requested from the server), never in clear.
        let port = try #require(ProcessInfo.processInfo.environment["DBM_A4_MYSQL_TLS_PORT"].flatMap(Int.init))
        let ca = try #require(ProcessInfo.processInfo.environment["DBM_A4_CA_FILE"].map { try Data(contentsOf: URL(fileURLWithPath: $0)) })
        // plain_probe / plain_probe2 are distinct fresh accounts so each full authentication really happens.
        for (mode, user) in [(MySQLTransportSecurity.plaintext, "plain_probe"), (.unverifiedTLS, "plain_probe2")] {
            let fresh = MySQLSettings(host: "localhost", port: port, database: "probe", username: user, password: "public-a4-fixture", transportSecurity: mode)
            let database = MySQLDatabase()
            _ = try await database.open(fresh)
            #expect(try await database.execute("SELECT 1").rows[0][0].value == "1")
            await database.close()
        }
        // A third fresh account through verified TLS (clear password inside the verified channel).
        _ = try await MySQLDatabase().open(MySQLSettings(host: "localhost", port: port, database: "probe", username: "plain_probe3",
                                                         password: "public-a4-fixture", certificateAuthority: ca))
        // Wrong password is still refused over the RSA path.
        let wrong = MySQLSettings(host: "localhost", port: port, database: "probe", username: "plain_probe", password: "wrong", transportSecurity: .plaintext)
        await #expect(throws: DatabaseError.mysqlConnectionFailed) { try await MySQLDatabase().open(wrong) }
    }

    @Test(.enabled(if: liveEnabled)) func liveServerWithoutTLSIsRefusedInBothTLSModes() async throws {
        // Neither TLS mode may fall back to plaintext when the server offers no TLS.
        for security in [MySQLTransportSecurity.verifiedTLS, .unverifiedTLS] {
            let plain = try #require(try mysqlLiveSettings("DBM_A4_MARIA_PLAIN_PORT", roots: security == .verifiedTLS ? "DBM_A4_CA_FILE" : nil, security: security))
            await #expect(throws: DatabaseError.mysqlTLSRequired) { try await MySQLDatabase().open(plain) }
        }
    }

    @Test(.enabled(if: liveEnabled), arguments: ["DBM_A4_MARIA_TLS_PORT", "DBM_A4_MYSQL_TLS_PORT"])
    func liveLimitsCancellationAndPhysicalRelease(portVariable: String) async throws {
        let settings = try #require(try mysqlLiveSettings(portVariable))
        let database = MySQLDatabase()
        _ = try await database.open(settings)
        let truncated = try await database.execute("SELECT n FROM probe.numbers", limits: QueryLimits(maxRows: 2))
        #expect(truncated.rows.count == 2 && truncated.truncated)
        await #expect(throws: DatabaseError.resultTooLarge) { try await database.execute("SELECT REPEAT('x',1048577)") }
        await #expect(throws: DatabaseError.resultTooLarge) {
            try await database.execute("SELECT REPEAT(CHAR(1),1000) FROM probe.numbers LIMIT 10", limits: QueryLimits(maxResultBytes: 8000))
        }
        await #expect(throws: DatabaseError.canceled) { try await database.execute("SELECT SLEEP(10)", limits: QueryLimits(timeout: 0.3)) }
        let task = Task { try await database.execute("SELECT SLEEP(20), 1") }
        let monitor = MySQLDatabase()
        _ = try await monitor.open(settings)
        let probe = "SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE INFO LIKE 'SELECT SLEEP(20)%' AND ID<>CONNECTION_ID()"
        var observedRunning = false
        for _ in 0..<100 {
            if try await monitor.execute(probe).rows[0][0].value == "1" { observedRunning = true; break }
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(observedRunning)
        let unrelated = MySQLDatabase()
        _ = try await unrelated.open(settings)
        let unrelatedQuery = Task { try await unrelated.execute("SELECT SLEEP(0.4), 77") }
        task.cancel()
        await #expect(throws: DatabaseError.canceled) { try await task.value }
        #expect(try await unrelatedQuery.value.rows[0][1].value == "77")
        await unrelated.close()
        // A fresh session proves the old server-side statement is gone, not only the Swift task.
        var released = false
        for _ in 0..<100 {
            if try await monitor.execute(probe).rows[0][0].value == "0" { released = true; break }
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(released)
        await monitor.close()
        #expect(try await database.execute("SELECT 42").rows[0][0].value == "42")
        let closing = Task { try await database.execute("SELECT SLEEP(10)") }
        try await Task.sleep(for: .milliseconds(300))
        await database.close()
        await #expect(throws: DatabaseError.canceled) { try await closing.value }
        await #expect(throws: DatabaseError.notOpen) { try await database.execute("SELECT 1") }
    }

    @Test(.enabled(if: liveEnabled)) func liveErrorsDoNotLeakSQLNamesOrSecrets() async throws {
        let settings = try #require(try mysqlLiveSettings())
        let database = MySQLDatabase()
        _ = try await database.open(settings)
        do { _ = try await database.execute("SELECT secret_column_name FROM probe.missing_table_name"); Issue.record("expected failure") }
        catch {
            let text = (error as? LocalizedError)?.errorDescription ?? ""
            #expect(!text.contains("secret_column_name") && !text.contains("missing_table_name") && !text.contains("public-a4-fixture") && !text.contains("probe"))
            #expect(error as? DatabaseError == .mysqlFailed(1146))
        }
        await database.close()
    }
}
