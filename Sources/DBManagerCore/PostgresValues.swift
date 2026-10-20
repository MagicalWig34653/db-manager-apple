// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import NIOCore
import PostgresNIO

// Binary wire representations are decoded without Decimal or floating date conversion.
enum PostgresValues {
    static func cell(_ source: PostgresCell, maxBytes: Int) throws -> Cell {
        guard let buffer = source.bytes else { return Cell(kind: .null) }
        guard buffer.readableBytes <= maxBytes else { throw DatabaseError.resultTooLarge }
        let result: Cell
        switch source.dataType {
        case .int2, .int4, .int8:
            result = Cell(kind: .integer, value: String(try source.decode(Int64.self)))
        case .float4, .float8:
            result = Cell(kind: .float, value: String(try source.decode(Double.self)))
        case .bool:
            result = Cell(kind: .boolean, value: try source.decode(Bool.self) ? "true" : "false")
        case .numeric:
            guard source.format == .binary else { throw DatabaseError.postgresFailed }
            result = Cell(kind: .decimal, value: try numeric(buffer, maxBytes: maxBytes))
        case .bytea:
            guard source.format == .binary else { throw DatabaseError.postgresFailed }
            result = Cell(kind: .binary, value: Data(buffer.readableBytesView).base64EncodedString())
        case .timestamp, .timestamptz:
            var copy = buffer
            guard copy.readableBytes == 8, let micros = copy.readInteger(as: Int64.self) else { throw DatabaseError.postgresFailed }
            result = Cell(kind: .timestamp, value: timestamp(micros, zoned: source.dataType == .timestamptz))
        case .date:
            var copy = buffer
            guard copy.readableBytes == 4, let days = copy.readInteger(as: Int32.self) else { throw DatabaseError.postgresFailed }
            if days == .max { result = Cell(kind: .timestamp, value: "infinity") }
            else if days == .min { result = Cell(kind: .timestamp, value: "-infinity") }
            else {
                let formatter = ISO8601DateFormatter()
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
                let text = formatter.string(from: Date(timeIntervalSince1970: Double(Int64(days) * 86_400 + 946_684_800)))
                result = Cell(kind: .timestamp, value: text.count == 10 ? text : "postgres-days-since-2000:\(days)")
            }
        case .text, .varchar, .bpchar, .name:
            guard let value = String(data: Data(buffer.readableBytesView), encoding: .utf8) else { throw DatabaseError.invalidText }
            result = Cell(kind: .text, value: value)
        case .uuid:
            result = Cell(kind: .text, value: try source.decode(UUID.self).uuidString.lowercased())
        case .json:
            guard let value = String(data: Data(buffer.readableBytesView), encoding: .utf8) else { throw DatabaseError.invalidText }
            result = Cell(kind: .text, value: value)
        case .jsonb:
            var copy = buffer
            guard copy.readInteger(as: UInt8.self) == 1,
                  let value = String(data: Data(copy.readableBytesView), encoding: .utf8) else { throw DatabaseError.invalidText }
            result = Cell(kind: .text, value: value)
        default:
            // Unknown/extension/array/interval types keep exact bytes and the column OID.
            result = Cell(kind: .binary, value: Data(buffer.readableBytesView).base64EncodedString())
        }
        // Raw wire and decoded representations are independently bounded (numeric expands).
        if result.kind != .binary, (result.value?.utf8.count ?? 0) > maxBytes { throw DatabaseError.resultTooLarge }
        return result
    }

    static func numeric(_ buffer: ByteBuffer, maxBytes: Int) throws -> String {
        var bytes = buffer
        guard let count = bytes.readInteger(as: Int16.self), count >= 0,
              let weight = bytes.readInteger(as: Int16.self),
              let sign = bytes.readInteger(as: UInt16.self),
              let scale = bytes.readInteger(as: UInt16.self), scale <= 16383,
              bytes.readableBytes == Int(count) * 2 else { throw DatabaseError.postgresFailed }
        switch sign {
        case 0xC000: return "NaN"
        case 0xD000: return "infinity"
        case 0xF000: return "-infinity"
        case 0, 0x4000: break
        default: throw DatabaseError.postgresFailed
        }
        let integerGroups = max(0, Int(weight) + 1)
        let fractionalGroups = (Int(scale) + 3) / 4
        guard max(1, integerGroups * 4) + Int(scale) + 2 <= maxBytes else { throw DatabaseError.resultTooLarge }
        var groups: [Int] = []
        for _ in 0..<count {
            guard let digit = bytes.readInteger(as: UInt16.self), digit < 10000 else { throw DatabaseError.postgresFailed }
            groups.append(Int(digit))
        }
        func group(at exponent: Int) -> Int {
            let offset = Int(weight) - exponent
            return groups.indices.contains(offset) ? groups[offset] : 0
        }
        var integer = ""
        if integerGroups > 0 {
            for exponent in stride(from: integerGroups - 1, through: 0, by: -1) {
                let value = String(group(at: exponent))
                integer += integer.isEmpty ? value : String(repeating: "0", count: 4 - value.count) + value
            }
        } else { integer = "0" }
        var fraction = ""
        if fractionalGroups > 0 {
            for index in 1...fractionalGroups {
                let value = String(group(at: -index))
                fraction += String(repeating: "0", count: 4 - value.count) + value
            }
            fraction = String(fraction.prefix(Int(scale)))
        }
        let negative = sign == 0x4000 && groups.contains(where: { $0 != 0 })
        return (negative ? "-" : "") + integer + (scale > 0 ? "." + fraction : "")
    }

    static func timestamp(_ microseconds: Int64, zoned: Bool) -> String {
        if microseconds == .max { return "infinity" }
        if microseconds == .min { return "-infinity" }
        var seconds = microseconds / 1_000_000
        var fraction = microseconds % 1_000_000
        if fraction < 0 { seconds -= 1; fraction += 1_000_000 }
        // Integral seconds are exact throughout Int64 microsecond range. Fraction never uses Double.
        let date = Date(timeIntervalSince1970: Double(seconds) + 946_684_800)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        let text = formatter.string(from: date)
        // Preserve unusual out-of-calendar-range values explicitly instead of inventing a date.
        guard text.count == 20, text.hasSuffix("Z") else {
            return "postgres-microseconds-since-2000:\(microseconds)" + (zoned ? ":UTC" : ":local")
        }
        let digits = String(fraction)
        return String(text.dropLast()) + "." + String(repeating: "0", count: 6 - digits.count) + digits + (zoned ? "Z" : "")
    }
}
