import Darwin
import Foundation

/// Atomic file replacement that survives power loss: the data is flushed to the device (`F_FULLFSYNC`, which on
/// macOS also flushes the drive cache; plain `fsync` does not) BEFORE the rename publishes it, and the containing
/// directory is flushed afterwards so the rename itself is durable. Foundation's `.atomic` write does neither, so a
/// crash could leave a zero-length file under the final name.
///
/// Used for small, rarely written control files (the recovery fence ledger). Document saves keep their existing
/// protocol: a full device flush on every save has a visible latency cost and is a separate decision.
enum DurableFileWriter {
    typealias Sync = @Sendable (Int32) -> Int32

    /// `F_FULLFSYNC`, falling back to plain `fsync` ONLY when the filesystem does not support the full flush. Any other
    /// failure (EIO, ...) is reported: a plain `fsync` that then succeeds would claim durability the device never gave.
    static let fullSync: Sync = { descriptor in
        flush(descriptor, fullFlush: { fcntl($0, F_FULLFSYNC) }, plainFlush: { fsync($0) })
    }

    static func flush(_ descriptor: Int32, fullFlush: Sync, plainFlush: Sync) -> Int32 {
        if fullFlush(descriptor) == 0 {
            return 0
        }
        guard [ENOTSUP, EINVAL, ENOTTY].contains(errno) else { return -1 }
        return plainFlush(descriptor)
    }

    /// Replaces `url` with `data`. Throws only BEFORE the rename publishes the new file (the old file is then intact);
    /// once published it never throws, because a caller told "failed" would keep its old in-memory state while disk
    /// already holds the new one. Returns whether the directory flush that makes the rename itself durable succeeded.
    @discardableResult
    static func write(_ data: Data, to url: URL, sync: Sync = fullSync) throws -> Bool {
        let directory = url.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        do {
            try data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let written = Darwin.write(
                        descriptor,
                        buffer.baseAddress.map { $0 + offset },
                        buffer.count - offset
                    )
                    if written < 0 {
                        if errno == EINTR {
                            continue
                        }
                        throw posixError()
                    }
                    offset += written
                }
            }
            guard sync(descriptor) == 0 else { throw posixError() }
        } catch {
            close(descriptor)
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        // Exactly one close on every path: a descriptor number is released even when close() reports an error, and
        // may already belong to another thread, so it must never be closed a second time.
        let closeResult = close(descriptor)
        let closeError = errno
        guard closeResult == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(closeError))
        }
        guard rename(temporary.path, url.path) == 0 else {
            let error = posixError()
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        let directoryDescriptor = open(directory.path, O_RDONLY | O_CLOEXEC)
        guard directoryDescriptor >= 0 else { return false }
        defer { close(directoryDescriptor) }
        return sync(directoryDescriptor) == 0
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
