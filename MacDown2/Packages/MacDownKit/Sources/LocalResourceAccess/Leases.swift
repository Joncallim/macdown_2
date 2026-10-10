import Darwin
import Foundation

/// An opened directory that is the authority for a set of reads. The descriptor is private: callers can neither
/// extract nor close it, and it is closed exactly once, after any in-flight read has finished. The pathname the lease
/// was created from is kept only to detect that the name has since been redirected.
public final class DirectoryLease: @unchecked Sendable {
    let owned: OwnedDescriptor
    public let identity: ResourceIdentity
    /// The canonical path the directory was opened at; used for the in-root symlink hint and the changed-root check.
    let canonicalPath: String

    public init(opening url: URL) throws(ResourceReadError) {
        guard let canonical = realpath(url.path, nil) else { throw .unavailable(errno) }
        let canonicalPath = String(cString: canonical)
        free(canonical)
        // The canonical path has no symlinks left, so refusing any here means a component swapped for a symlink after
        // `realpath` fails instead of pinning whatever it points at.
        let descriptor = open(canonicalPath, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW_ANY)
        guard descriptor >= 0 else { throw errno == ELOOP ? .denied : .unavailable(errno) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            let failure = errno
            Darwin.close(descriptor)
            throw .unavailable(failure)
        }
        owned = OwnedDescriptor(descriptor)
        identity = ResourceIdentity(info)
        self.canonicalPath = canonicalPath
    }

    public func close() {
        owned.requestClose()
    }

    /// Whether the granted directory's current name still refers to the granted directory.
    func nameStillRefersToGrantedDirectory() -> Bool {
        var info = stat()
        guard lstat(canonicalPath, &info) == 0 else { return false }
        return ResourceIdentity(info) == identity
    }
}

/// A single opened regular file: the authority to snapshot exactly that file, and nothing about its parent directory.
public final class FileLease: @unchecked Sendable {
    let owned: OwnedDescriptor
    public let identity: ResourceIdentity
    public let name: String

    public init(opening url: URL) throws(ResourceReadError) {
        // The caller explicitly granted THIS path, so symlinks in it (including `/var` -> `/private/var` ancestors or
        // a user-chosen alias) are resolved once here; the open itself then refuses any symlink, so a component
        // swapped for a symlink after resolution fails instead of being followed.
        guard let canonical = realpath(url.path, nil) else { throw .unavailable(errno) }
        let canonicalPath = String(cString: canonical)
        free(canonical)
        let descriptor = open(canonicalPath, O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW_ANY)
        guard descriptor >= 0 else { throw errno == ELOOP ? .denied : .unavailable(errno) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            let failure = errno
            Darwin.close(descriptor)
            throw .unavailable(failure)
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            Darwin.close(descriptor)
            throw .nonRegular
        }
        owned = OwnedDescriptor(descriptor)
        identity = ResourceIdentity(info)
        name = (canonicalPath as NSString).lastPathComponent
    }

    public func close() {
        owned.requestClose()
    }
}
