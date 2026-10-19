import Darwin
import Foundation

/// Test barriers around the real constrained child-directory open. Production uses `.none`.
struct ChildDirectoryOpenHooks: Sendable {
    var beforeOpen: (@Sendable () -> Void)?
    var afterOpen: (@Sendable () -> Void)?

    static let none = ChildDirectoryOpenHooks()
}

/// An opened directory that is the authority for a set of reads. The descriptor is private: callers can neither
/// extract nor close it, and it is closed exactly once, after any in-flight read has finished. The pathname the lease
/// was created from is kept only to detect that the name has since been redirected.
public final class DirectoryLease: @unchecked Sendable {
    private struct ChildCandidate {
        let canonicalPath: String
        let relativePath: String
        let expectedIdentity: ResourceIdentity
    }

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

    private init(owned: OwnedDescriptor, identity: ResourceIdentity, canonicalPath: String) {
        self.owned = owned
        self.identity = identity
        self.canonicalPath = canonicalPath
    }

    /// Pins a child directory using this lease's descriptor, never an absolute-path reopen. The `ResourceReference`
    /// is a parsed relative directory name; an empty reference is not needed because callers can retain this lease
    /// when the document is directly inside the granted root. This primitive does not mint a new user grant.
    public func childDirectory(_ reference: ResourceReference) throws(ResourceReadError) -> DirectoryLease {
        try childDirectory(reference, hooks: .none)
    }

    func childDirectory(
        _ reference: ResourceReference,
        hooks: ChildDirectoryOpenHooks
    ) throws(ResourceReadError) -> DirectoryLease {
        let candidate = try childCandidate(for: reference)
        hooks.beforeOpen?()
        let result = try owned.withDescriptor { parent throws(ResourceReadError) in
            let descriptor = openat(
                parent, candidate.relativePath,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW_ANY | O_RESOLVE_BENEATH
            )
            guard descriptor >= 0 else { throw Self.mapChildOpenError(errno) }
            var openedInfo = stat()
            guard fstat(descriptor, &openedInfo) == 0 else {
                let failure = errno
                Darwin.close(descriptor)
                throw .unavailable(failure)
            }
            guard (openedInfo.st_mode & S_IFMT) == S_IFDIR else {
                Darwin.close(descriptor)
                throw .nonRegular
            }
            let opened = ResourceIdentity(openedInfo)
            guard opened == candidate.expectedIdentity else {
                Darwin.close(descriptor)
                throw .changedRoot
            }
            hooks.afterOpen?()
            return (descriptor, opened)
        }
        guard let (descriptor, opened) = result else { throw .leaseClosed }
        let child = DirectoryLease(owned: OwnedDescriptor(descriptor), identity: opened,
                                   canonicalPath: candidate.canonicalPath)
        guard nameStillRefersToGrantedDirectory(), child.nameStillRefersToGrantedDirectory() else {
            child.close()
            throw .changedRoot
        }
        return child
    }

    private func childCandidate(for reference: ResourceReference) throws(ResourceReadError) -> ChildCandidate {
        // ResourceReference has a public components initializer. Validate even if a caller did not use `parse`.
        guard !reference.components.isEmpty, reference.components.allSatisfy(Self.isSafeChildComponent) else {
            throw .invalidReference
        }
        guard nameStillRefersToGrantedDirectory() else { throw .changedRoot }

        // This pathname is only a hint for legitimate in-root symlinks and a changed-name check. It cannot
        // authorize a read. The security-bearing step is `openat` from the held parent descriptor.
        let candidate = canonicalPath + "/" + reference.relativePath
        guard let resolved = realpath(candidate, nil) else { throw Self.mapChildOpenError(errno) }
        defer { free(resolved) }
        let childPath = String(cString: resolved)
        let prefix = Array((canonicalPath.hasSuffix("/") ? canonicalPath : canonicalPath + "/").utf8)
        let bytes = Array(childPath.utf8)
        guard bytes.count > prefix.count, bytes.starts(with: prefix),
              let relative = String(validating: bytes[prefix.count...], as: UTF8.self)
        else { throw .denied }

        // A replacement between this strict identity observation and the real open is rejected, even if the
        // replacement is another ordinary directory beneath the grant.
        var expectedInfo = stat()
        guard lstat(childPath, &expectedInfo) == 0 else { throw Self.mapChildOpenError(errno) }
        guard (expectedInfo.st_mode & S_IFMT) == S_IFDIR else { throw .nonRegular }
        return ChildCandidate(canonicalPath: childPath, relativePath: relative,
                              expectedIdentity: ResourceIdentity(expectedInfo))
    }

    private static func isSafeChildComponent(_ component: String) -> Bool {
        !component.isEmpty && component != "." && component != ".." && !component.utf8.contains(0)
            && !component.utf8.contains(UInt8(ascii: "/"))
    }

    private static func mapChildOpenError(_ code: Int32) -> ResourceReadError {
        switch code {
        case ELOOP, EACCES, EPERM, ENOTCAPABLE, EXDEV: .denied
        case ENOTDIR: .nonRegular
        case EINVAL, ENOTSUP: .unsupportedEnforcement
        default: .unavailable(code)
        }
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
