// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import NIOCore
import NIOPosix
import NIOSSL
import NIOTLS

/// Warning level a UI can show for a transport choice. There is no automatic switch between modes.
public enum MySQLSecurityWarning: Int, Sendable, Comparable {
    /// Encrypted and the server identity is verified.
    case none = 0
    /// Encrypted, but the server certificate and host name are NOT checked: an active attacker can
    /// impersonate the server and read credentials and data.
    case serverIdentityUnverified = 1
    /// Nothing is encrypted: credentials (as scrambles) and all data are readable and modifiable on the path.
    case noEncryption = 2
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// How the client protects one MySQL/MariaDB connection. The mode is chosen explicitly per connection;
/// the client never falls back from one mode to a weaker one. If the server does not offer TLS while
/// a TLS mode is selected, the connection is aborted before any authentication byte is sent.
public enum MySQLTransportSecurity: Sendable, Equatable, CaseIterable {
    /// Default. TLS >= 1.2 with certificate chain and host name verification.
    case verifiedTLS
    /// Explicitly chosen: TLS without certificate or host name verification (encryption against passive
    /// observers only). Not combinable with a CA file.
    case unverifiedTLS
    /// Explicitly chosen: no TLS at all, also for non-loopback hosts. Passwords only ever leave as
    /// scrambles (mysql_native_password, caching_sha2_password fast auth); caching_sha2 full
    /// authentication would need the clear password and is refused. Not combinable with a CA file.
    case plaintext

    public var warning: MySQLSecurityWarning {
        switch self {
        case .verifiedTLS: .none
        case .unverifiedTLS: .serverIdentityUnverified
        case .plaintext: .noEncryption
        }
    }
    public var usesTLS: Bool { self != .plaintext }
    public var verifiesServerIdentity: Bool { self == .verifiedTLS }
}

struct MySQLConnectionConfig: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    var description: String { "MySQLConnectionConfig(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
    let host: String
    let port: Int
    let database: String
    let username: String
    let password: [UInt8]
    let tls: NIOSSLContext?
    let security: MySQLTransportSecurity
    var serverName: String? { security.verifiesServerIdentity ? host : nil }
    let connectTimeout: TimeInterval
}

/// Inbound side of the channel. Reads are demand driven: after two queued chunks auto-read is
/// paused, so a hostile or fast server cannot make the client buffer unbounded data.
final class MySQLInboundHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    private let lock = NSLock()
    private var chunks: [ByteBuffer] = []
    private var waiter: CheckedContinuation<ByteBuffer, Error>?
    private var failure: Error?
    private var paused = false
    private var channel: Channel?
    private var tlsPromise: EventLoopPromise<Void>?

    func handlerAdded(context: ChannelHandlerContext) {
        lock.lock(); channel = context.channel; lock.unlock()
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        lock.lock()
        if let waiter { self.waiter = nil; lock.unlock(); waiter.resume(returning: buffer); return }
        chunks.append(buffer)
        if chunks.count >= 2, !paused {
            paused = true
            lock.unlock()
            _ = context.channel.setOption(ChannelOptions.autoRead, value: false)
        } else { lock.unlock() }
    }
    func channelInactive(context: ChannelHandlerContext) { fail(MySQLTransportError.closed) }
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        fail(error)
        context.close(promise: nil)
    }
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is TLSUserEvent {
            lock.lock(); let promise = tlsPromise; tlsPromise = nil; lock.unlock()
            promise?.succeed(())
        }
        context.fireUserInboundEventTriggered(event)
    }

    private func fail(_ error: Error) {
        lock.lock()
        if failure == nil { failure = error }
        let pending = waiter, tls = tlsPromise
        waiter = nil; tlsPromise = nil
        let stored = failure!
        lock.unlock()
        pending?.resume(throwing: stored)
        tls?.fail(stored)
    }

    /// STARTTLS-injection guard: anything queued before TLS is active is attacker-controlled
    /// (a real server sends nothing until it sees the ClientHello) and aborts the connection.
    func requireNoQueuedData() throws {
        lock.lock(); defer { lock.unlock() }
        guard chunks.isEmpty else { throw DatabaseError.mysqlProtocolError }
    }

    func setTLSPromise(_ promise: EventLoopPromise<Void>) {
        lock.lock()
        if let failure { lock.unlock(); promise.fail(failure); return }
        tlsPromise = promise
        lock.unlock()
    }

    func next() async throws -> ByteBuffer {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if !chunks.isEmpty {
                let chunk = chunks.removeFirst()
                let resume = paused && chunks.count < 2
                if resume { paused = false }
                let channel = self.channel
                lock.unlock()
                continuation.resume(returning: chunk)
                if resume, let channel {
                    channel.eventLoop.execute {
                        _ = channel.setOption(ChannelOptions.autoRead, value: true)
                        channel.read()
                    }
                }
            } else if let failure {
                lock.unlock(); continuation.resume(throwing: failure)
            } else {
                waiter = continuation; lock.unlock()
            }
        }
    }
}

enum MySQLTransportError: Error { case closed }

/// One physical connection, driven strictly sequentially by a single task.
final class MySQLConnection: @unchecked Sendable {
    private let channel: Channel
    private let inbound: MySQLInboundHandler
    private var assembler = MySQLPacketAssembler()
    private(set) var greeting: MySQLGreeting?
    private(set) var tlsActive = false
    var isMariaDB: Bool { greeting?.isMariaDB ?? false }

    private init(channel: Channel, inbound: MySQLInboundHandler) {
        self.channel = channel; self.inbound = inbound
    }

    /// Connects, requires TLS (unless the explicit loopback option removed the context) and authenticates.
    /// `install` runs as soon as the socket exists so cancellation can close a half-open handshake.
    static func connect(_ config: MySQLConnectionConfig, install: (MySQLConnection) -> Void) async throws -> MySQLConnection {
        let inbound = MySQLInboundHandler()
        let channel: Channel
        do {
            channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                .connectTimeout(.milliseconds(Int64(config.connectTimeout * 1000)))
                .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .channelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: 1)
                .channelInitializer { $0.pipeline.addHandler(inbound) }
                .connect(host: config.host, port: config.port).get()
        } catch { throw DatabaseError.mysqlConnectionFailed }
        let connection = MySQLConnection(channel: channel, inbound: inbound)
        install(connection)
        do {
            try Task.checkCancellation()
            try await connection.handshake(config)
            return connection
        } catch {
            connection.forceClose()
            throw error
        }
    }

    func forceClose() { channel.close(promise: nil) }
    func close() async { try? await channel.close().get() }

    // MARK: Packets

    private func readPacket(maxPayload: Int) async throws -> ByteBuffer {
        while true {
            if let payload = try assembler.nextPayload(maxPayload: maxPayload) { return payload }
            assembler.append(try await inbound.next())
        }
    }

    private func writePacket(_ payload: [UInt8]) async throws {
        // Both directions share one sequence counter within a command; commands restart it at 0.
        var sequence = assembler.expectedSequence
        let framed = try MySQLPacketAssembler.frame(payload, sequence: &sequence)
        assembler.expectedSequence = sequence
        try await channel.writeAndFlush(framed).get()
    }

    // MARK: Handshake

    private func handshake(_ config: MySQLConnectionConfig) async throws {
        let first = try await readPacket(maxPayload: 65_536)
        if first.getInteger(at: first.readerIndex, as: UInt8.self) == 0xFF { throw DatabaseError.mysqlConnectionFailed }
        let greeting = try MySQLGreeting.parse(first)
        self.greeting = greeting
        let required = MySQLCapability.protocol41 | MySQLCapability.secureConnection
        guard greeting.capabilities & required == required else { throw DatabaseError.mysqlUnsupportedAuth }
        var flags = MySQLCapability.longPassword | MySQLCapability.longFlag | MySQLCapability.protocol41
            | MySQLCapability.transactions | MySQLCapability.secureConnection | MySQLCapability.pluginAuth
            | MySQLCapability.pluginAuthLengthEncodedClientData
        if !config.database.isEmpty { flags |= MySQLCapability.connectWithDatabase }
        if let context = config.tls {
            // Fail closed before sending anything: an attacker stripping CLIENT_SSL gains nothing.
            guard greeting.capabilities & MySQLCapability.ssl != 0 else { throw DatabaseError.mysqlTLSRequired }
            flags |= MySQLCapability.ssl
            try await writePacket(Self.preamble(flags: flags))
            // The server sends nothing until it sees the TLS ClientHello.
            guard assembler.isEmpty else { throw DatabaseError.mysqlProtocolError }
            try inbound.requireNoQueuedData()
            let promise = channel.eventLoop.makePromise(of: Void.self)
            inbound.setTLSPromise(promise)
            do {
                let serverName = config.serverName
                try await channel.eventLoop.submit { [channel, inbound] in
                    // Runs on the event loop: no read can slip in between this check and the TLS handler.
                    try inbound.requireNoQueuedData()
                    try channel.pipeline.syncOperations.addHandler(
                        NIOSSLClientHandler(context: context, serverHostname: serverName), position: .first)
                }.get()
                try await promise.futureResult.get()
            } catch let known as DatabaseError { throw known
            } catch { throw DatabaseError.mysqlConnectionFailed }
            try inbound.requireNoQueuedData()
            tlsActive = true
        }
        var response = Self.preamble(flags: flags)
        response += Array(config.username.utf8) + [0]
        var plugin = greeting.pluginName
        var scramble = greeting.scramble
        guard let authData = MySQLAuth.response(plugin: plugin, password: config.password, scramble: scramble) else {
            throw DatabaseError.mysqlUnsupportedAuth
        }
        var lengthEncoded = ByteBuffer(); lengthEncoded.writeMySQLLengthEncodedInteger(UInt64(authData.count))
        response += lengthEncoded.readableBytesView + authData
        if !config.database.isEmpty { response += Array(config.database.utf8) + [0] }
        response += Array(plugin.utf8) + [0]
        try await writePacket(response)
        // Authentication loop: OK, ERR, auth switch, or caching_sha2 more-data.
        for _ in 0..<4 {
            var packet = try await readPacket(maxPayload: 65_536)
                switch packet.getInteger(at: packet.readerIndex, as: UInt8.self) {
            case 0x00: return
            case 0xFF: throw DatabaseError.mysqlConnectionFailed
            case 0xFE:
                packet.moveReaderIndex(forwardBy: 1)
                guard let name = packet.readMySQLNulTerminated(maxLength: 64) else { throw DatabaseError.mysqlProtocolError }
                let requested = String(decoding: name, as: UTF8.self)
                // Only plugins answered with a scramble are supported (never the clear password), so a
                // switch cannot leak the password even without TLS. In plaintext mode the user already
                // accepted that the path is unprotected; unsupported plugins are refused below.
                plugin = requested
                scramble = packet.readBytes(length: packet.readableBytes) ?? []
                if scramble.last == 0 { scramble.removeLast() }
                guard let next = MySQLAuth.response(plugin: plugin, password: config.password, scramble: scramble) else {
                    throw DatabaseError.mysqlUnsupportedAuth
                }
                try await writePacket(next)
            case 0x01:
                packet.moveReaderIndex(forwardBy: 1)
                switch packet.readInteger(as: UInt8.self) {
                case 0x03: continue              // fast authentication succeeded; OK follows
                case 0x04:
                    // Full caching_sha2 authentication. The clear password only ever travels inside
                    // verified TLS; without TLS we refuse instead of using the RSA key exchange.
                    guard tlsActive else { throw DatabaseError.mysqlUnsupportedAuth }
                    try await writePacket(config.password + [0])
                default: throw DatabaseError.mysqlProtocolError
                }
            default: throw DatabaseError.mysqlProtocolError
            }
        }
        throw DatabaseError.mysqlProtocolError
    }

    /// Capability flags, max packet size, utf8mb4_general_ci and the 23 reserved zero bytes.
    private static func preamble(flags: UInt32) -> [UInt8] {
        var buffer = ByteBuffer()
        buffer.writeInteger(flags, endianness: .little)
        buffer.writeInteger(UInt32(0x00FF_FFFF), endianness: .little)
        buffer.writeInteger(45 as UInt8)
        buffer.writeRepeatingByte(0, count: 23)
        return Array(buffer.readableBytesView)
    }

    // MARK: Commands

    struct Result: Sendable {
        var columns: [MySQLColumnDefinition] = []
        var rows: [[Cell]] = []
        var rowsAffected: String?
        var truncated = false
    }

    /// COM_QUERY with streaming, bounded row decoding. No multi-statement or LOCAL INFILE support.
    func query(_ sql: String, limits: QueryLimits) async throws -> Result {
        assembler.resetSequence()
        let payload = [UInt8(0x03)] + Array(sql.utf8)
        guard payload.count <= 1_048_577 else { throw DatabaseError.resultTooLarge }
        try await writePacket(payload)
        let packetLimit = min(limits.maxResultBytes, 16_000_000) + 1024
        var first = try await readPacket(maxPayload: 65_536)
        var result = Result()
        switch first.getInteger(at: first.readerIndex, as: UInt8.self) {
        case 0xFF: throw Self.serverError(MySQLErrorPacket.parse(first))
        case 0x00:
            first.moveReaderIndex(forwardBy: 1)
            result.rowsAffected = first.readMySQLLengthEncodedInteger().map(String.init)
            return result
        case 0xFB: throw DatabaseError.mysqlProtocolError   // LOCAL INFILE was never enabled; refuse.
        default: break
        }
        guard let count = first.readMySQLLengthEncodedInteger(), count > 0, count <= 1024 else { throw DatabaseError.mysqlProtocolError }
        var bytes = 256
        for _ in 0..<count {
            let packet = try await readPacket(maxPayload: 65_536)
            if packet.getInteger(at: packet.readerIndex, as: UInt8.self) == 0xFF { throw Self.serverError(MySQLErrorPacket.parse(packet)) }
            let definition = try MySQLColumnDefinition.parse(packet, maxNameBytes: limits.maxCellBytes)
            result.columns.append(definition)
            bytes += definition.name.utf8.count + 64
        }
        guard bytes <= limits.maxResultBytes else { throw DatabaseError.resultTooLarge }
        let eof = try await readPacket(maxPayload: 65_536)
        if eof.getInteger(at: eof.readerIndex, as: UInt8.self) == 0xFF { throw Self.serverError(MySQLErrorPacket.parse(eof)) }
        guard eof.getInteger(at: eof.readerIndex, as: UInt8.self) == 0xFE, eof.readableBytes < 9 else { throw DatabaseError.mysqlProtocolError }
        while true {
            try Task.checkCancellation()
            var row = try await readPacket(maxPayload: packetLimit)
            let marker = row.getInteger(at: row.readerIndex, as: UInt8.self)
            if marker == 0xFE, row.readableBytes < 9 { return result }
            if marker == 0xFF { throw Self.serverError(MySQLErrorPacket.parse(row)) }
            if result.rows.count == limits.maxRows { result.truncated = true; return result }
            var cells: [Cell] = []
            cells.reserveCapacity(result.columns.count)
            for column in result.columns {
                if row.getInteger(at: row.readerIndex, as: UInt8.self) == 0xFB {
                    row.moveReaderIndex(forwardBy: 1)
                    cells.append(Cell(kind: .null))
                } else {
                    let value = try row.readMySQLLengthEncodedBytes(maxLength: limits.maxCellBytes)
                    cells.append(try MySQLValues.cell(value, column: column, maxBytes: limits.maxCellBytes))
                }
            }
            guard row.readableBytes == 0 else { throw DatabaseError.mysqlProtocolError }
            bytes += try JSONEncoder().encode(cells).count + 1
            guard bytes <= limits.maxResultBytes else { throw DatabaseError.resultTooLarge }
            result.rows.append(cells)
        }
    }

    /// Authenticated thread id for `KILL QUERY`; the greeting's id is unauthenticated.
    func authenticatedConnectionID() async throws -> UInt32 {
        let small = QueryLimits(maxRows: 2, maxCellBytes: 32, maxResultBytes: 4096, timeout: 5)
        let result = try await query("SELECT CONNECTION_ID()", limits: small)
        guard result.rows.count == 1, result.rows[0].count == 1, let text = result.rows[0][0].value,
              let id = UInt32(text) else { throw DatabaseError.mysqlProtocolError }
        return id
    }

    static func serverError(_ packet: MySQLErrorPacket) -> DatabaseError {
        switch packet.code {
        // Interrupted, killed, max_execution_time (MySQL) and max_statement_time (MariaDB) exceeded.
        case 1317, 1927, 3024, 1969: .canceled
        default: .mysqlFailed(packet.code)
        }
    }
}
