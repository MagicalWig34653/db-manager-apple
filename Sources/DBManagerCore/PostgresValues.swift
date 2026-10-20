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
            result = Cell(kind: .timestamp, value: date(days))
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

    static func date(_ days: Int32) -> String {
        if days == .max { return "infinity" }
        if days == .min { return "-infinity" }
        let civil = civilDate(Int64(days))
        return civil.text + (civil.bc ? " BC" : "")
    }

    static func timestamp(_ microseconds: Int64, zoned: Bool) -> String {
        if microseconds == .max { return "infinity" }
        if microseconds == .min { return "-infinity" }
        let dayMicroseconds: Int64 = 86_400_000_000
        let days = floorDivide(microseconds, by: dayMicroseconds)
        // Remainder adjustment avoids multiplying a floored negative day near Int64.min.
        var withinDay = microseconds % dayMicroseconds
        if withinDay < 0 { withinDay += dayMicroseconds }
        let civil = civilDate(days)
        let hours = withinDay / 3_600_000_000
        let minutes = withinDay / 60_000_000 % 60
        let seconds = withinDay / 1_000_000 % 60
        let fraction = withinDay % 1_000_000
        return civil.text + "T" + padded(hours, width: 2) + ":" + padded(minutes, width: 2)
            + ":" + padded(seconds, width: 2) + "." + padded(fraction, width: 6)
            + (zoned ? "Z" : "") + (civil.bc ? " BC" : "")
    }

    // PostgreSQL uses the proleptic Gregorian calendar, including before 1582.
    // Astronomical year zero is 1 BC. Count its leap day before mapping the era.
    private static func daysBeforeYear(_ year: Int64) -> Int64 {
        365 * year + floorDivide(year + 3, by: 4) - floorDivide(year + 99, by: 100)
            + floorDivide(year + 399, by: 400)
    }

    private static func civilDate(_ postgresDays: Int64) -> (text: String, bc: Bool) {
        // 2000*365 + 500 leap years - 20 centuries + 5 fourth centuries.
        let absolute = postgresDays + 730_485
        // Covers every Int32 date and every day reachable from Int64 microseconds.
        var lower: Int64 = -6_000_000
        var upper: Int64 = 6_000_001
        while lower + 1 < upper {
            let middle = lower + (upper - lower) / 2
            if daysBeforeYear(middle) <= absolute { lower = middle }
            else { upper = middle }
        }
        let year = lower
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let lengths: [Int64] = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        var day = absolute - daysBeforeYear(year)
        var month = 0
        while day >= lengths[month] { day -= lengths[month]; month += 1 }
        let displayYear = year <= 0 ? 1 - year : year
        return (padded(displayYear, width: 4) + "-" + padded(Int64(month + 1), width: 2)
                + "-" + padded(day + 1, width: 2), year <= 0)
    }

    private static func floorDivide(_ value: Int64, by divisor: Int64) -> Int64 {
        let quotient = value / divisor
        return value % divisor < 0 ? quotient - 1 : quotient
    }

    private static func padded(_ value: Int64, width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}
