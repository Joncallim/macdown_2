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

    /// `F_FULLFSYNC`, falling back to `fsync` on a filesystem that does not support it.
    static let fullSync: Sync = { descriptor in
        if fcntl(descriptor, F_FULLFSYNC) == 0 {
            return 0
        }
        return fsync(descriptor)
    }

    static func write(_ data: Data, to url: URL, sync: Sync = fullSync) throws {
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
            guard close(descriptor) == 0 else { throw posixError() }
        } catch {
            close(descriptor)
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        guard rename(temporary.path, url.path) == 0 else {
            let error = posixError()
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        let directoryDescriptor = open(directory.path, O_RDONLY | O_CLOEXEC)
        guard directoryDescriptor >= 0 else { throw posixError() }
        defer { close(directoryDescriptor) }
        guard sync(directoryDescriptor) == 0 else { throw posixError() }
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
