// SPDX-License-Identifier: AGPL-3.0-only
import CryptoKit
import Foundation
import NIOCore

// Minimal MySQL/MariaDB client protocol primitives (text protocol only).
// Everything here is pure and testable without a socket.

enum MySQLCapability {
    static let longPassword: UInt32 = 0x0000_0001
    static let connectWithDatabase: UInt32 = 0x0000_0008
    static let longFlag: UInt32 = 0x0000_0004
    static let protocol41: UInt32 = 0x0000_0200
    static let ssl: UInt32 = 0x0000_0800
    static let transactions: UInt32 = 0x0000_2000
    static let secureConnection: UInt32 = 0x0000_8000
    static let pluginAuth: UInt32 = 0x0008_0000
    static let pluginAuthLengthEncodedClientData: UInt32 = 0x0020_0000
}

extension ByteBuffer {
    /// Returns nil for the NULL marker (0xFB), the reserved 0xFF byte and truncated input.
    mutating func readMySQLLengthEncodedInteger() -> UInt64? {
        guard let first = readInteger(as: UInt8.self) else { return nil }
        switch first {
        case 0..<0xFB: return UInt64(first)
        case 0xFC: return readInteger(endianness: .little, as: UInt16.self).map(UInt64.init)
        case 0xFD:
            guard let bytes = readBytes(length: 3) else { return nil }
            return UInt64(bytes[0]) | UInt64(bytes[1]) << 8 | UInt64(bytes[2]) << 16
        case 0xFE: return readInteger(endianness: .little, as: UInt64.self)
        default: return nil
        }
    }

    mutating func writeMySQLLengthEncodedInteger(_ value: UInt64) {
        switch value {
        case 0..<0xFB: writeInteger(UInt8(value))
        case 0xFB..<0x1_0000: writeInteger(0xFC as UInt8); writeInteger(UInt16(value), endianness: .little)
        case 0x1_0000..<0x100_0000:
            writeInteger(0xFD as UInt8)
            writeBytes([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF)])
        default: writeInteger(0xFE as UInt8); writeInteger(value, endianness: .little)
        }
    }

    mutating func readMySQLNulTerminated(maxLength: Int = 4096) -> [UInt8]? {
        let view = readableBytesView
        guard let end = view.prefix(maxLength + 1).firstIndex(of: 0) else { return nil }
        let count = end - view.startIndex
        let bytes = readBytes(length: count)
        moveReaderIndex(forwardBy: 1)
        return bytes
    }

    /// Length-encoded string; `nil` result for NULL marker is expressed through `isNull`.
    mutating func readMySQLLengthEncodedBytes(maxLength: Int) throws -> [UInt8] {
        guard let length = readMySQLLengthEncodedInteger() else { throw DatabaseError.mysqlProtocolError }
        guard length <= UInt64(maxLength) else { throw DatabaseError.resultTooLarge }
        guard let bytes = readBytes(length: Int(length)) else { throw DatabaseError.mysqlProtocolError }
        return bytes
    }
}

/// Splits a TLS-decrypted byte stream into logical packets. Enforces sequence numbers and
/// a hard payload ceiling before any payload is buffered beyond one 4-byte header.
struct MySQLPacketAssembler {
    private var buffer = ByteBuffer()
    var expectedSequence: UInt8 = 0
    var isEmpty: Bool { buffer.readableBytes == 0 }

    mutating func resetSequence() { expectedSequence = 0 }
    mutating func append(_ chunk: ByteBuffer) { var copy = chunk; buffer.writeBuffer(&copy) }

    /// Returns nil when more input is needed. Multi-packet payloads (0xFFFFFF fragments) are joined.
    mutating func nextPayload(maxPayload: Int) throws -> ByteBuffer? {
        var probe = buffer
        var payload = ByteBuffer()
        var sequence = expectedSequence
        while true {
            guard let header = probe.readBytes(length: 4) else { return nil }
            let length = Int(header[0]) | Int(header[1]) << 8 | Int(header[2]) << 16
            guard header[3] == sequence else { throw DatabaseError.mysqlProtocolError }
            guard payload.readableBytes + length <= maxPayload else { throw DatabaseError.resultTooLarge }
            guard var part = probe.readSlice(length: length) else { return nil }
            payload.writeBuffer(&part)
            sequence &+= 1
            if length < 0xFF_FFFF { break }
        }
        buffer = probe
        buffer.discardReadBytes()
        expectedSequence = sequence
        return payload
    }

    /// Frames one logical payload (below 16 MiB) and advances a caller-owned sequence counter.
    static func frame(_ payload: [UInt8], sequence: inout UInt8) throws -> ByteBuffer {
        guard payload.count < 0xFF_FFFF else { throw DatabaseError.resultTooLarge }
        var out = ByteBuffer()
        out.reserveCapacity(payload.count + 4)
        out.writeBytes([UInt8(payload.count & 0xFF), UInt8((payload.count >> 8) & 0xFF), UInt8((payload.count >> 16) & 0xFF), sequence])
        out.writeBytes(payload)
        sequence &+= 1
        return out
    }
}

struct MySQLGreeting {
    let serverVersion: String
    let threadID: UInt32
    let capabilities: UInt32
    let scramble: [UInt8]
    let pluginName: String
    var isMariaDB: Bool { serverVersion.localizedCaseInsensitiveContains("mariadb") }

    static func parse(_ payload: ByteBuffer) throws -> MySQLGreeting {
        var buffer = payload
        guard buffer.readInteger(as: UInt8.self) == 0x0A,
              let version = buffer.readMySQLNulTerminated(maxLength: 256),
              let thread = buffer.readInteger(endianness: .little, as: UInt32.self),
              let part1 = buffer.readBytes(length: 8),
              buffer.readInteger(as: UInt8.self) == 0,
              let low = buffer.readInteger(endianness: .little, as: UInt16.self) else { throw DatabaseError.mysqlProtocolError }
        var capabilities = UInt32(low)
        var authLength = 0
        var part2: [UInt8] = []
        if buffer.readableBytes > 0 {
            guard buffer.readInteger(as: UInt8.self) != nil,   // character set
                  buffer.readInteger(endianness: .little, as: UInt16.self) != nil, // status
                  let high = buffer.readInteger(endianness: .little, as: UInt16.self),
                  let length = buffer.readInteger(as: UInt8.self),
                  buffer.readBytes(length: 10) != nil else { throw DatabaseError.mysqlProtocolError }
            capabilities |= UInt32(high) << 16
            authLength = Int(length)
            if capabilities & MySQLCapability.secureConnection != 0 {
                let count = max(13, authLength - 8)
                guard let bytes = buffer.readBytes(length: min(count, buffer.readableBytes)) else { throw DatabaseError.mysqlProtocolError }
                part2 = bytes
            }
        }
        var plugin = "mysql_native_password"
        if capabilities & MySQLCapability.pluginAuth != 0, let name = buffer.readMySQLNulTerminated(maxLength: 64) ?? buffer.readBytes(length: buffer.readableBytes) {
            plugin = String(decoding: name, as: UTF8.self)
        }
        // The scramble is 20 bytes followed by a NUL filler in the second part.
        var scramble = part1 + part2
        if scramble.last == 0 { scramble.removeLast() }
        guard scramble.count >= 8 else { throw DatabaseError.mysqlProtocolError }
        return MySQLGreeting(serverVersion: String(decoding: version, as: UTF8.self), threadID: thread,
                             capabilities: capabilities, scramble: scramble, pluginName: plugin)
    }
}

enum MySQLAuth {
    static let nativePlugin = "mysql_native_password"
    static let cachingSHA2Plugin = "caching_sha2_password"

    static func response(plugin: String, password: [UInt8], scramble: [UInt8]) -> [UInt8]? {
        switch plugin {
        case nativePlugin: nativePassword(password: password, scramble: scramble)
        case cachingSHA2Plugin: cachingSHA2(password: password, scramble: scramble)
        default: nil
        }
    }

    static func nativePassword(password: [UInt8], scramble: [UInt8]) -> [UInt8] {
        guard !password.isEmpty else { return [] }
        let stage1 = Array(Insecure.SHA1.hash(data: password))
        let stage2 = Array(Insecure.SHA1.hash(data: stage1))
        let mix = Array(Insecure.SHA1.hash(data: scramble + stage2))
        return zip(stage1, mix).map { $0 ^ $1 }
    }

    static func cachingSHA2(password: [UInt8], scramble: [UInt8]) -> [UInt8] {
        guard !password.isEmpty else { return [] }
        let stage1 = Array(SHA256.hash(data: password))
        let stage2 = Array(SHA256.hash(data: stage1))
        let mix = Array(SHA256.hash(data: stage2 + scramble))
        return zip(stage1, mix).map { $0 ^ $1 }
    }
}

struct MySQLErrorPacket {
    let code: Int32
    static func parse(_ payload: ByteBuffer) -> MySQLErrorPacket {
        var buffer = payload
        _ = buffer.readInteger(as: UInt8.self)
        // Message and SQL state are deliberately discarded: they may echo SQL, paths or user names.
        return MySQLErrorPacket(code: Int32(buffer.readInteger(endianness: .little, as: UInt16.self) ?? 0))
    }
}

struct MySQLColumnDefinition: Sendable {
    let name: String
    let characterSet: UInt16
    let type: UInt8
    let flags: UInt16
    var isBinary: Bool { characterSet == 63 }
    var isUnsigned: Bool { flags & 32 != 0 }

    static func parse(_ payload: ByteBuffer, maxNameBytes: Int) throws -> MySQLColumnDefinition {
        var buffer = payload
        // catalog, schema, table, org_table (skipped), then name and org_name.
        for _ in 0..<4 { _ = try buffer.readMySQLLengthEncodedBytes(maxLength: 4096) }
        let name = try buffer.readMySQLLengthEncodedBytes(maxLength: maxNameBytes)
        _ = try buffer.readMySQLLengthEncodedBytes(maxLength: 4096)
        guard buffer.readMySQLLengthEncodedInteger() == 0x0C,
              let charset = buffer.readInteger(endianness: .little, as: UInt16.self),
              buffer.readInteger(endianness: .little, as: UInt32.self) != nil,
              let type = buffer.readInteger(as: UInt8.self),
              let flags = buffer.readInteger(endianness: .little, as: UInt16.self) else { throw DatabaseError.mysqlProtocolError }
        guard let text = String(data: Data(name), encoding: .utf8) else { throw DatabaseError.invalidText }
        return MySQLColumnDefinition(name: text, characterSet: charset, type: type, flags: flags)
    }

    var typeName: String {
        let base: String
        switch type {
        case 0x00, 0xF6: base = "DECIMAL"
        case 1: base = "TINYINT"
        case 2: base = "SMALLINT"
        case 3: base = "INT"
        case 4: base = "FLOAT"
        case 5: base = "DOUBLE"
        case 6: base = "NULL"
        case 7: base = "TIMESTAMP"
        case 8: base = "BIGINT"
        case 9: base = "MEDIUMINT"
        case 10, 14: base = "DATE"
        case 11: base = "TIME"
        case 12: base = "DATETIME"
        case 13: base = "YEAR"
        case 15, 253: base = isBinary ? "VARBINARY" : "VARCHAR"
        case 16: base = "BIT"
        case 245: base = "JSON"
        case 247: base = "ENUM"
        case 248: base = "SET"
        case 249: base = isBinary ? "TINYBLOB" : "TINYTEXT"
        case 250: base = isBinary ? "MEDIUMBLOB" : "MEDIUMTEXT"
        case 251: base = isBinary ? "LONGBLOB" : "LONGTEXT"
        case 252: base = isBinary ? "BLOB" : "TEXT"
        case 254: base = isBinary ? "BINARY" : "CHAR"
        case 255: base = "GEOMETRY"
        default: base = "TYPE \(type)"
        }
        return isUnsigned && [1, 2, 3, 8, 9].contains(type) ? base + " UNSIGNED" : base
    }
}

// Text-protocol values stay textual so DECIMAL, BIGINT UNSIGNED and fractional seconds are never rounded.
enum MySQLValues {
    static func cell(_ bytes: [UInt8]?, column: MySQLColumnDefinition, maxBytes: Int) throws -> Cell {
        guard let bytes else { return Cell(kind: .null) }
        guard bytes.count <= maxBytes else { throw DatabaseError.resultTooLarge }
        func text() throws -> String {
            guard let value = String(data: Data(bytes), encoding: .utf8) else { throw DatabaseError.invalidText }
            return value
        }
        func binary() -> Cell { Cell(kind: .binary, value: Data(bytes).base64EncodedString()) }
        switch column.type {
        case 0x00, 0xF6: return Cell(kind: .decimal, value: try text())
        case 1, 2, 3, 8, 9, 13: return Cell(kind: .integer, value: try text())
        case 4, 5: return Cell(kind: .float, value: try text())
        case 16, 255: return binary()
        case 7, 12:
            let value = try text()
            if let iso = timestamp(value, zoned: column.type == 7) { return Cell(kind: .timestamp, value: iso) }
            return Cell(kind: .text, value: value)
        case 10, 14:
            let value = try text()
            return isPlausibleDate(value) ? Cell(kind: .timestamp, value: value) : Cell(kind: .text, value: value)
        case 11, 245, 247, 248: return Cell(kind: .text, value: try text())
        case 15, 249, 250, 251, 252, 253, 254:
            return column.isBinary ? binary() : Cell(kind: .text, value: try text())
        default: return binary()   // Unknown extension types keep their exact bytes.
        }
    }

    /// `YYYY-MM-DD HH:MM:SS[.ffffff]` becomes ISO-8601; zero dates stay text because they are not instants.
    static func timestamp(_ value: String, zoned: Bool) -> String? {
        guard value.count >= 19, value.count <= 26, let space = value.firstIndex(of: " "),
              isPlausibleDate(String(value[..<space])) else { return nil }
        var iso = value
        iso.replaceSubrange(space...space, with: "T")
        return zoned ? iso + "Z" : iso
    }

    static func isPlausibleDate(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return false }
        return year > 0 && (1...12).contains(month) && (1...31).contains(day)
    }
}
