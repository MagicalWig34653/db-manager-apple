// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Security

/// caching_sha2_password "full authentication" without a verified TLS channel, as done by the official
/// MySQL clients: the server's RSA public key is requested, the password (NUL terminated, XORed with the
/// nonce) is encrypted with RSA-OAEP (SHA-1) and only the ciphertext is sent. The clear password never
/// leaves the client. Uses the Security framework (macOS/iOS system component); no extra dependency.
/// Honest limit: the key arrives over the same unauthenticated channel, so an active attacker can
/// substitute its own key and then recovers the password. Confidentiality here is against passive
/// observers only, which is exactly the protection the user accepted by choosing these modes.
enum MySQLRSA {
    static let minimumModulusBits = 2048
    static let maximumModulusBits = 8192

    /// Returns the PKCS#1 RSAPublicKey DER and the modulus size in bits. Accepts SubjectPublicKeyInfo and PKCS#1 PEM.
    static func parsePublicKey(pem: [UInt8]) throws -> (der: Data, bits: Int) {
        guard pem.count <= 4096, let text = String(bytes: pem, encoding: .utf8) else { throw DatabaseError.mysqlProtocolError }
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = lines.first, let last = lines.last, lines.count >= 3,
              (first == "-----BEGIN PUBLIC KEY-----" && last == "-----END PUBLIC KEY-----")
                || (first == "-----BEGIN RSA PUBLIC KEY-----" && last == "-----END RSA PUBLIC KEY-----"),
              let decoded = Data(base64Encoded: lines.dropFirst().dropLast().joined()) else { throw DatabaseError.mysqlProtocolError }
        var reader = DERReader(Array(decoded))
        var pkcs1 = Array(decoded)
        if first.contains("RSA PUBLIC KEY") == false {
            var spki = try reader.sequence()
            var algorithm = try spki.sequence()
            // rsaEncryption 1.2.840.113549.1.1.1
            guard try algorithm.element(tag: 0x06) == [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01] else { throw DatabaseError.mysqlProtocolError }
            let bitString = try spki.element(tag: 0x03)
            guard bitString.first == 0, spki.isAtEnd, reader.isAtEnd else { throw DatabaseError.mysqlProtocolError }
            pkcs1 = Array(bitString.dropFirst())
        }
        var key = DERReader(pkcs1)
        var body = try key.sequence()
        guard key.isAtEnd else { throw DatabaseError.mysqlProtocolError }
        let modulus = Array(try body.element(tag: 0x02).drop { $0 == 0 })
        let exponent = Array(try body.element(tag: 0x02).drop { $0 == 0 })
        guard body.isAtEnd, let top = modulus.first, let low = modulus.last, low & 1 == 1,
              !exponent.isEmpty, exponent.count <= 4, exponent.last! & 1 == 1 else { throw DatabaseError.mysqlProtocolError }
        let exponentValue = exponent.reduce(0 as UInt64) { $0 << 8 | UInt64($1) }
        let bits = (modulus.count - 1) * 8 + (8 - top.leadingZeroBitCount)
        guard exponentValue >= 65_537, (minimumModulusBits...maximumModulusBits).contains(bits) else { throw DatabaseError.mysqlUnsupportedAuth }
        return (Data(pkcs1), bits)
    }

    static func xorWithNonce(password: [UInt8], nonce: [UInt8]) -> [UInt8] {
        let source = password + [0]
        return source.enumerated().map { $0.element ^ nonce[$0.offset % nonce.count] }
    }

    static func encryptPassword(password: [UInt8], nonce: [UInt8], publicKeyPEM: [UInt8]) throws -> [UInt8] {
        guard !nonce.isEmpty else { throw DatabaseError.mysqlProtocolError }
        let parsed = try parsePublicKey(pem: publicKeyPEM)
        let message = xorWithNonce(password: password, nonce: nonce)
        // OAEP with SHA-1 leaves modulus bytes minus 42 bytes of room.
        guard message.count <= parsed.bits / 8 - 42 else { throw DatabaseError.mysqlUnsupportedAuth }
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(parsed.der as CFData, attributes as CFDictionary, nil),
              let encrypted = SecKeyCreateEncryptedData(key, .rsaEncryptionOAEPSHA1, Data(message) as CFData, nil) else {
            throw DatabaseError.mysqlUnsupportedAuth
        }
        return Array(encrypted as Data)
    }
}

/// Strict, bounded DER reader (definite lengths up to 2 bytes, no indefinite forms).
struct DERReader {
    private let bytes: [UInt8]
    private var position = 0
    init(_ bytes: [UInt8]) { self.bytes = bytes }
    var isAtEnd: Bool { position == bytes.count }

    mutating func element(tag: UInt8) throws -> [UInt8] {
        guard position < bytes.count, bytes[position] == tag else { throw DatabaseError.mysqlProtocolError }
        position += 1
        guard position < bytes.count else { throw DatabaseError.mysqlProtocolError }
        var length = Int(bytes[position]); position += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard (1...2).contains(count), position + count <= bytes.count else { throw DatabaseError.mysqlProtocolError }
            length = 0
            for _ in 0..<count { length = length << 8 | Int(bytes[position]); position += 1 }
        }
        guard length <= bytes.count - position else { throw DatabaseError.mysqlProtocolError }
        defer { position += length }
        return Array(bytes[position..<position + length])
    }
    mutating func sequence() throws -> DERReader { DERReader(try element(tag: 0x30)) }
}
