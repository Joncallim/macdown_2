import Darwin
import Foundation

/// Test seams that sit around the REAL syscalls so a test can replace filesystem objects at the exact moment a race
/// would matter. Production passes `.none`.
struct ResourceReadHooks: Sendable {
    var beforeOpen: (@Sendable () -> Void)?
    var afterOpen: (@Sendable () -> Void)?
    /// Called before each chunk read with the number of bytes read so far.
    var beforeChunk: (@Sendable (Int) -> Void)?

    static let none = ResourceReadHooks()
}

/// Reads one file beneath a pinned directory (or one pinned file) into immutable bytes. This is the blocking core: a
/// bounded I/O executor wraps it later, and this layer is where containment is decided. The security-bearing step is
/// the `openat` relative to the directory descriptor with `O_RESOLVE_BENEATH | O_NOFOLLOW_ANY`; the canonical
/// in-root symlink hint only chooses WHICH relative path to open and authorises nothing.
public enum ContainedResourceReader {
    static let openFlags = O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW_ANY | O_RESOLVE_BENEATH
    static let chunkSize = 64 * 1024

    public static func read(
        _ reference: ResourceReference,
        in directory: DirectoryLease,
        maxBytes: Int,
        cancellation: ResourceCancellation = ResourceCancellation()
    ) throws(ResourceReadError) -> ResourceSnapshot {
        try read(reference, in: directory, maxBytes: maxBytes, cancellation: cancellation, hooks: .none)
    }

    static func read(
        _ reference: ResourceReference,
        in directory: DirectoryLease,
        maxBytes: Int,
        cancellation: ResourceCancellation,
        hooks: ResourceReadHooks
    ) throws(ResourceReadError) -> ResourceSnapshot {
        guard !cancellation.isCancelled else { throw .cancelled }
        guard directory.nameStillRefersToGrantedDirectory() else { throw .changedRoot }
        let relative = try constrainedRelativePath(for: reference, in: directory)
        hooks.beforeOpen?()
        let result = try directory.owned.withDescriptor { rootDescriptor throws(ResourceReadError) in
            let descriptor = openat(rootDescriptor, relative, openFlags)
            guard descriptor >= 0 else { throw mapOpenError(errno) }
            defer { Darwin.close(descriptor) }
            hooks.afterOpen?()
            return try snapshot(
                descriptor: descriptor,
                name: reference.components.last ?? "",
                maxBytes: maxBytes,
                cancellation: cancellation,
                hooks: hooks
            )
        }
        guard let result else { throw .cancelled }
        return result
    }

    /// Single-file grant: the lease IS the authority, no path is involved.
    public static func read(
        _ lease: FileLease,
        maxBytes: Int,
        cancellation: ResourceCancellation = ResourceCancellation()
    ) throws(ResourceReadError) -> ResourceSnapshot {
        guard !cancellation.isCancelled else { throw .cancelled }
        let result = try lease.owned.withDescriptor { descriptor throws(ResourceReadError) in
            try snapshot(
                descriptor: descriptor,
                name: lease.name,
                maxBytes: maxBytes,
                cancellation: cancellation,
                hooks: .none
            )
        }
        guard let result else { throw .cancelled }
        return result
    }

    // MARK: - Steps

    /// The in-root symlink hint: resolve the reference once against the granted directory's canonical path and require
    /// the result to remain beneath it, then return the path relative to the root. This is advisory — the strict
    /// `openat` below re-checks containment at open time.
    private static func constrainedRelativePath(
        for reference: ResourceReference,
        in directory: DirectoryLease
    ) throws(ResourceReadError) -> String {
        let candidate = directory.canonicalPath + "/" + reference.relativePath
        guard let resolved = realpath(candidate, nil) else { throw mapOpenError(errno) }
        defer { free(resolved) }
        let canonical = String(cString: resolved)
        let prefix = directory.canonicalPath.hasSuffix("/") ? directory.canonicalPath : directory.canonicalPath + "/"
        guard canonical.hasPrefix(prefix), canonical.count > prefix.count else { throw .denied }
        return String(canonical.dropFirst(prefix.count))
    }

    private static func mapOpenError(_ code: Int32) -> ResourceReadError {
        switch code {
        case ELOOP, EACCES, EPERM, ENOTCAPABLE, EXDEV: .denied
        default: .unavailable(code)
        }
    }

    private static func snapshot(
        descriptor: Int32,
        name: String,
        maxBytes: Int,
        cancellation: ResourceCancellation,
        hooks: ResourceReadHooks
    ) throws(ResourceReadError) -> ResourceSnapshot {
        var before = stat()
        guard fstat(descriptor, &before) == 0 else { throw .unavailable(errno) }
        guard (before.st_mode & S_IFMT) == S_IFREG else { throw .nonRegular }
        guard before.st_size >= 0, Int64(before.st_size) <= Int64(maxBytes) else { throw .oversized }

        let bytes = try readAll(
            descriptor: descriptor,
            expectedSize: Int(before.st_size),
            maxBytes: maxBytes,
            cancellation: cancellation,
            hooks: hooks
        )

        var after = stat()
        guard fstat(descriptor, &after) == 0 else { throw .unavailable(errno) }
        guard unchanged(before, after, byteCount: bytes.count) else { throw .changedDuringRead }
        return ResourceSnapshot(
            bytes: bytes,
            identity: ResourceIdentity(after),
            name: name,
            mimeHint: MIMEHint.hint(forName: name)
        )
    }

    private static func readAll(
        descriptor: Int32,
        expectedSize: Int,
        maxBytes: Int,
        cancellation: ResourceCancellation,
        hooks: ResourceReadHooks
    ) throws(ResourceReadError) -> Data {
        var bytes = Data()
        bytes.reserveCapacity(expectedSize)
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while true {
            guard !cancellation.isCancelled else { throw .cancelled }
            hooks.beforeChunk?(bytes.count)
            let want = min(chunkSize, maxBytes - bytes.count + 1) // cap + 1 so growth past the cap is observable
            let count = Darwin.read(descriptor, &buffer, want)
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                throw .unavailable(errno)
            }
            if count == 0 {
                return bytes
            }
            let (total, overflow) = bytes.count.addingReportingOverflow(count)
            guard !overflow, total <= maxBytes else { throw .oversized }
            bytes.append(contentsOf: buffer[0 ..< count])
        }
    }

    private static func unchanged(_ before: stat, _ after: stat, byteCount: Int) -> Bool {
        ResourceIdentity(after) == ResourceIdentity(before)
            && after.st_size == before.st_size
            && after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec
            && after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec
            && Int64(byteCount) == Int64(after.st_size)
    }
}
