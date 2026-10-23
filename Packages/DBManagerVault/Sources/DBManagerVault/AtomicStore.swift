// SPDX-License-Identifier: AGPL-3.0-only
import CryptoKit
import Darwin
import Foundation

final class AtomicStore {
    private var directory: Int32 = -1
    private var lockFile: Int32 = -1
    let slot: String
    var filename: String { slot + ".vault" }

    init(root: URL, slot: String) throws {
        _ = try VaultCodec.identifier(slot)
        guard root.isFileURL, root.path.hasPrefix("/") else { throw StorageError.invalid }
        self.slot = slot
        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw StorageError.io }
        do {
            for component in root.path.split(separator: "/") {
                guard component != ".", component != ".." else { throw StorageError.invalid }
                let next = openat(descriptor, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw StorageError.io }
                Darwin.close(descriptor); descriptor = next
            }
            var metadata = stat()
            guard fstat(descriptor, &metadata) == 0, metadata.st_uid == geteuid(),
                  metadata.st_mode & 0o777 == 0o700 else { throw StorageError.invalid }
            directory = descriptor; descriptor = -1
            lockFile = openat(directory, ".vault-lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, mode_t(0o600))
            guard lockFile >= 0 else { throw StorageError.io }
            try check(lockFile)
            guard flock(lockFile, LOCK_EX | LOCK_NB) == 0 else { throw StorageError.busy }
        } catch {
            if descriptor >= 0 { Darwin.close(descriptor) }
            close(); throw error
        }
    }
    deinit { close() }
    func close() {
        if lockFile >= 0 { Darwin.close(lockFile); lockFile = -1 }
        if directory >= 0 { Darwin.close(directory); directory = -1 }
    }
    private func check(_ fd: Int32) throws {
        var s = stat()
        guard fstat(fd, &s) == 0, s.st_mode & S_IFMT == S_IFREG,
              s.st_uid == geteuid(), s.st_nlink == 1, s.st_mode & 0o777 == 0o600 else { throw StorageError.invalid }
    }
    func read(_ name: String? = nil) throws -> Data? {
        let name = name ?? filename
        guard name == filename || validTemporary(name) else { throw StorageError.invalid }
        let fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if fd < 0 && errno == ENOENT { return nil }
        guard fd >= 0 else { throw StorageError.io }
        defer { Darwin.close(fd) }
        try check(fd)
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, metadata.st_size >= 0,
              metadata.st_size <= VaultCodec.maxFileBytes else { throw StorageError.limit }
        var data = Data(count: Int(metadata.st_size))
        try data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw StorageError.io }
                offset += count
            }
        }
        var end = stat()
        guard fstat(fd, &end) == 0, end.st_size == metadata.st_size,
              end.st_mtimespec.tv_sec == metadata.st_mtimespec.tv_sec,
              end.st_mtimespec.tv_nsec == metadata.st_mtimespec.tv_nsec else { throw StorageError.conflict }
        return data
    }
    static func digest(_ data: Data) -> String { VaultCodec.hex(Data(SHA256.hash(data: data))) }
    func temporaryName() throws -> String { "s-" + (try VaultCodec.hex(VaultCodec.random(16))) + ".pending" }
    private func validTemporary(_ name: String) -> Bool {
        name.hasPrefix("s-") && name.hasSuffix(".pending") && name.count == 42
            && (try? VaultCodec.identifier(String(name.dropFirst(2).dropLast(8)))) != nil
    }
    func stage(_ data: Data, name: String) throws {
        guard validTemporary(name), !data.isEmpty, data.count <= VaultCodec.maxFileBytes else { throw StorageError.invalid }
        let fd = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw StorageError.io }
        defer { Darwin.close(fd) }
        try check(fd)
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw StorageError.io }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw StorageError.io }
        try syncDirectory()
    }
    func install(_ name: String, expectedDigest: String) throws {
        guard validTemporary(name), let bytes = try read(name), Self.digest(bytes) == expectedDigest else { throw StorageError.conflict }
        guard renameat(directory, name, directory, filename) == 0 else { throw StorageError.io }
    }
    func syncDirectory() throws { guard fsync(directory) == 0 else { throw StorageError.io } }
    func discard(_ name: String) throws {
        guard validTemporary(name) else { throw StorageError.invalid }
        if try read(name) != nil {
            guard unlinkat(directory, name, 0) == 0 else { throw StorageError.io }
            try syncDirectory()
        }
    }
}
