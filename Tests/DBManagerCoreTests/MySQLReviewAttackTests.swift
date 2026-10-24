// SPDX-License-Identifier: AGPL-3.0-only
// Independent reviewer attack tests for A4. Live cases need scripts/review-a4-fakeserver.py (DBM_A4R_DIR).
import Foundation
import NIOCore
import Testing
@testable import DBManagerCore

private let attackDir = ProcessInfo.processInfo.environment["DBM_A4R_DIR"]

private func port(_ mode: String) -> Int {
    guard let attackDir, let data = FileManager.default.contents(atPath: attackDir + "/ports.json"),
          let map = try? JSONSerialization.jsonObject(with: data) as? [String: Int], let p = map[mode] else { return 0 }
    return p
}
private func ca(_ name: String = "ca.pem") -> Data? { attackDir.flatMap { FileManager.default.contents(atPath: $0 + "/" + name) } }
private func events(_ mode: String) -> String {
    guard let attackDir, let s = try? String(contentsOfFile: attackDir + "/log-" + mode + ".json", encoding: .utf8) else { return "<no log>" }
    return s
}
private func outcome(_ mode: String, host: String = "localhost", roots: String? = "ca.pem", security: MySQLTransportSecurity = .verifiedTLS,
                     password: String = "s3cret-PW", timeout: TimeInterval = 10, limits: QueryLimits? = nil, sql: String? = nil) async -> String {
    let settings = MySQLSettings(host: host, port: port(mode), database: "db", username: "u", password: password,
                                 certificateAuthority: roots.flatMap { ca($0) }, transportSecurity: security)
    let database = MySQLDatabase()
    let start = ContinuousClock.now
    var text: String
    do {
        let objs = try await database.open(settings, timeout: timeout); text = "OPEN-OK \(objs.map { $0.name })"
        if let sql {
            let r = try await database.execute(sql, limits: limits ?? QueryLimits(timeout: timeout))
            text = "OK rows=\(r.rows.count) truncated=\(r.truncated)"
        } else { }
    } catch { text = "\(error)" }
    await database.close()
    let ms = start.duration(to: .now).components.seconds * 1000 + start.duration(to: .now).components.attoseconds / 1_000_000_000_000_000
    return "\(text) [\(ms)ms]"
}

private let live = attackDir != nil

@Suite(.serialized, .enabled(if: live)) struct ReviewAttackLive {
    @Test func report() async throws {
        var out: [String] = []
        func rec(_ k: String, _ v: String) { out.append("\(k): \(v)") }
        rec("nossl", await outcome("nossl")); rec("nossl.log", events("nossl"))
        // Explicit TLS modes never fall back to plaintext: still aborted before any client byte.
        rec("nossl-unverified", await outcome("nossl", roots: nil, security: .unverifiedTLS)); rec("nossl-unverified.log", events("nossl"))
        for m in ["expired", "otherca", "wronghost"] { rec(m + "-unverified", await outcome(m, roots: nil, security: .unverifiedTLS)) }
        for m in ["expired", "otherca", "wronghost"] { rec(m, await outcome(m)); rec(m + ".log", events(m)) }
        rec("good-host-localhost", await outcome("good")); rec("good.log", events("good"))
        rec("ipcert-host-127", await outcome("ipcert", host: "127.0.0.1")); rec("ipcert.log", events("ipcert"))
        rec("ipcert-host-localhost", await outcome("ipcert"));
        rec("good-ip-host(127.0.0.1 vs DNS cert)", await outcome("good", host: "127.0.0.1"))
        rec("noca-system-store", await outcome("good", roots: nil))
        rec("tls_good_fullauth", await outcome("tls_good_fullauth")); rec("tls_good_fullauth.log", events("tls_good_fullauth"))
        rec("plain_fullauth", await outcome("plain_fullauth", host: "127.0.0.1", roots: nil, security: .plaintext)); rec("plain_fullauth.log", events("plain_fullauth"))
        rec("plain_switch_clear", await outcome("plain_switch_clear", host: "127.0.0.1", roots: nil, security: .plaintext)); rec("plain_switch_clear.log", events("plain_switch_clear"))
        for p in ["mysql_clear_password", "mysql_native_password", "sha256_password", "client_ed25519", "mysql_old_password"] {
            rec("switch_" + p, await outcome("switch_" + p)); rec("switch_" + p + ".log", events("switch_" + p))
        }
        // Second-review additions: unverified TLS is still encrypted, still refuses downgrade, still never sends the password in plaintext.
        rec("unverified-good-tls_fullauth", await outcome("tls_good_fullauth", roots: nil, security: .unverifiedTLS)); rec("unverified-fullauth.log", events("tls_good_fullauth"))
        rec("unverified-switch_clear", await outcome("switch_mysql_clear_password", roots: nil, security: .unverifiedTLS))
        rec("plaintext-nossl-server", await outcome("nossl", host: "127.0.0.1", roots: nil, security: .plaintext))
        try out.joined(separator: "\n").write(toFile: attackDir! + "/report-live.txt", atomically: true, encoding: .utf8)
    }

    @Test func injection() async throws {
        var out: [String] = []
        for m in ["inject:-1", "inject:0", "inject:0.0005", "inject:0.002", "inject:0.005", "inject:0.02"] {
            var results: [String: Int] = [:]
            for i in 0..<20 {
                let r = i % 2 == 0 ? await outcome(m) : await outcome(m, roots: nil, security: .unverifiedTLS)
                let key = r.hasPrefix("OPEN-OK") ? "FORGED-ACCEPTED" : String(r.prefix(40))
                results[key, default: 0] += 1
            }
            out.append("\(m): \(results)")
        }
        try out.joined(separator: "\n").write(toFile: attackDir! + "/report-inject.txt", atomically: true, encoding: .utf8)
    }

    @Test func malicious() async throws {
        var out: [String] = []
        let plain = MySQLTransportSecurity.plaintext
        for m in ["hdr_huge", "badseq", "stall", "rows_endless", "bigcell", "bigcell2", "colcount", "zerocols", "drip", "invalid_utf8", "shortrow", "errpacket", "infile", "rows_fat", "idstall"] {
            let r = await outcome("mal_" + m, host: "127.0.0.1", roots: nil, security: plain, timeout: 3,
                                  limits: QueryLimits(maxRows: 1000, timeout: 3), sql: "SELECT mal")
            out.append("\(m): \(r)")
        }
        try out.joined(separator: "\n").write(toFile: attackDir! + "/report-mal.txt", atomically: true, encoding: .utf8)
    }
}

// MARK: in-process mutation fuzz of the pure parsers (any trap/crash fails the run)

private struct LCG { var s: UInt64; mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s >> 33 } }

@Test func reviewFuzzParsersNeverTrapOrHang() throws {
    var rng = LCG(s: 0xA4)
    let greeting: [UInt8] = [0x0A] + Array("8.4.0\0".utf8) + [1, 0, 0, 0] + Array(1...8) + [0, 0xFF, 0xF7, 45, 2, 0, 0xFF, 0x81, 21] + [UInt8](repeating: 0, count: 10) + Array(9...20) + [0] + Array("caching_sha2_password\0".utf8)
    var col = ByteBuffer()
    for s in ["def", "", "", "", "v", "v"] { col.writeMySQLLengthEncodedInteger(UInt64(s.utf8.count)); col.writeString(s) }
    col.writeBytes([0x0C, 45, 0, 255, 0, 0, 0, 253, 0, 0, 0, 0, 0])
    let colBytes = Array(col.readableBytesView)
    let seeds = [greeting, colBytes, [0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x41], Array("2026-10-20 12:34:56.123456".utf8)]
    var parsed = 0
    for iteration in 0..<60_000 {
        var bytes = seeds[iteration % seeds.count]
        for _ in 0..<(1 + Int(rng.next() % 4)) {
            switch rng.next() % 4 {
            case 0 where !bytes.isEmpty: bytes[Int(rng.next()) % bytes.count] = UInt8(truncatingIfNeeded: rng.next())
            case 1 where !bytes.isEmpty: bytes.removeLast(Int(rng.next()) % bytes.count)
            case 2: bytes.insert(UInt8(truncatingIfNeeded: rng.next()), at: bytes.isEmpty ? 0 : Int(rng.next()) % bytes.count)
            default: bytes += (0..<Int(rng.next() % 8)).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            }
        }
        let buffer = ByteBuffer(bytes: bytes)
        if (try? MySQLGreeting.parse(buffer)) != nil { parsed += 1 }
        _ = try? MySQLColumnDefinition.parse(buffer, maxNameBytes: 1024)
        var b2 = buffer; _ = b2.readMySQLLengthEncodedInteger()
        var b3 = buffer; _ = try? b3.readMySQLLengthEncodedBytes(maxLength: 4096)
        var b4 = buffer; _ = b4.readMySQLNulTerminated(maxLength: 64)
        var assembler = MySQLPacketAssembler()
        assembler.append(buffer)
        _ = try? assembler.nextPayload(maxPayload: 65_536)
        for type: UInt8 in [0, 1, 7, 10, 11, 12, 16, 245, 252, 253, 255, 99] {
            let def = MySQLColumnDefinition(name: "v", characterSet: iteration % 2 == 0 ? 63 : 45, type: type, flags: UInt16(iteration & 0xFFFF))
            _ = try? MySQLValues.cell(bytes, column: def, maxBytes: 1 << 20)
            _ = def.typeName
        }
    }
    #expect(parsed >= 0)
}

@Test func reviewAssemblerFragmentationAndHostileLengths() throws {
    // 0xFFFFFF fragment + 5-byte tail is joined; sequence must advance across fragments.
    var assembler = MySQLPacketAssembler()
    var wire = ByteBuffer()
    wire.writeBytes([0xFF, 0xFF, 0xFF, 0]); wire.writeRepeatingByte(7, count: 0xFF_FFFF)
    wire.writeBytes([5, 0, 0, 1]); wire.writeRepeatingByte(9, count: 5)
    // Feed in odd-sized chunks, include an incomplete state at every step.
    var offset = 0
    var result: ByteBuffer?
    while offset < wire.readableBytes {
        let n = min(1_000_003, wire.readableBytes - offset)
        assembler.append(wire.getSlice(at: offset, length: n)!)
        offset += n
        result = try assembler.nextPayload(maxPayload: 20_000_000)
        if offset < wire.readableBytes { #expect(result == nil) }
    }
    #expect(result?.readableBytes == 0xFF_FFFF + 5)
    #expect(assembler.expectedSequence == 2)
    // Exactly 0xFFFFFF followed by empty terminator packet.
    var a2 = MySQLPacketAssembler()
    var w2 = ByteBuffer(); w2.writeBytes([0xFF, 0xFF, 0xFF, 0]); w2.writeRepeatingByte(1, count: 0xFF_FFFF); w2.writeBytes([0, 0, 0, 1])
    a2.append(w2)
    #expect(try a2.nextPayload(maxPayload: 20_000_000)?.readableBytes == 0xFF_FFFF)
    // Oversized header refused before payload is present.
    var a3 = MySQLPacketAssembler(); a3.append(ByteBuffer(bytes: [0xFF, 0xFF, 0xFF, 0]))
    #expect(throws: DatabaseError.resultTooLarge) { try a3.nextPayload(maxPayload: 65_536) }
    // Many fragments each below the cap but summing above is refused.
    var a4 = MySQLPacketAssembler(); var w4 = ByteBuffer()
    for i in 0..<3 { w4.writeBytes([0xFF, 0xFF, 0xFF, UInt8(i)]); w4.writeRepeatingByte(0, count: 0xFF_FFFF) }
    a4.append(w4)
    #expect(throws: DatabaseError.resultTooLarge) { try a4.nextPayload(maxPayload: 20_000_000) }
}
