import Darwin
import Foundation

/// Filesystem boundary for the disabled, validated HTML path. Open directory
/// descriptors keep every staging operation in the directory actually checked;
/// changing a pathname to a symlink cannot redirect a later read or write.
/// Other processes can still change exported files after this operation returns.
enum ValidatedFilePublication {
    private final class DirectoryHandle {
        let descriptor: Int32

        init(_ descriptor: Int32) {
            self.descriptor = descriptor
        }

        deinit {
            _ = Darwin.close(descriptor)
        }
    }

    private struct Stamp: Equatable {
        let device: UInt64
        let inode: UInt64
        let kind: mode_t
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64

        init(_ info: stat) {
            device = UInt64(info.st_dev)
            inode = UInt64(info.st_ino)
            kind = info.st_mode & mode_t(S_IFMT)
            size = info.st_size
            modifiedSeconds = Int64(info.st_mtimespec.tv_sec)
            modifiedNanoseconds = Int64(info.st_mtimespec.tv_nsec)
            changedSeconds = Int64(info.st_ctimespec.tv_sec)
            changedNanoseconds = Int64(info.st_ctimespec.tv_nsec)
        }

        func sameDirectory(as other: Stamp) -> Bool {
            kind == mode_t(S_IFDIR) && other.kind == kind
                && device == other.device && inode == other.inode
        }
    }

    private struct StagedCompanions {
        let directory: DirectoryHandle
        let stamp: Stamp
        let entries: [(name: String, stamp: Stamp)]
        let urls: [URL]
    }

    static func write(
        _ validated: ValidatedExportHTML, lease: ExportLifetimeLease,
        afterCompanionDirectoryOpened: (() -> Void)?, beforePromotion: (() -> Void)?
    ) throws -> ExportResult {
        guard case let .html(url, _) = validated.target, validated.bytesAreIntact(),
              safeName(url.lastPathComponent),
              validated.assetsDirectoryName == ExportHTMLWriter.assetsDirectoryName(for: url)
        else { throw ExportError.validatedPublicationRejected }
        try Task.checkCancellation()
        try lease.checkActive()

        let parentURL = url.deletingLastPathComponent()
        let parent = try openParent(parentURL)
        let parentStamp = try directoryStamp(parent.descriptor)
        let staged = try stageCompanions(
            validated, in: parent, nextTo: parentURL,
            lease: lease, afterOpening: afterCompanionDirectoryOpened
        )

        beforePromotion?()
        // Revocation and this final synchronous verification/promotion share
        // one cutoff. Descriptor-relative rename cannot follow a swapped path.
        try lease.withPublicationCutoff {
            try verify(validated, parent: parent, parentPath: parentURL.path,
                       parentStamp: parentStamp, staged: staged)
            try promote(validated.utf8, as: url.lastPathComponent, in: parent.descriptor)
        }
        return ExportResult(primaryFile: url, companionFiles: staged?.urls ?? [],
                            diagnostics: validated.diagnostics)
    }

    private static func openParent(_ url: URL) throws -> DirectoryHandle {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ExportError.invalidDestination(url.path) }
        return DirectoryHandle(descriptor)
    }

    private static func stageCompanions(
        _ validated: ValidatedExportHTML,
        in parent: DirectoryHandle, nextTo parentURL: URL,
        lease: ExportLifetimeLease, afterOpening: (() -> Void)?
    ) throws -> StagedCompanions? {
        guard case let .html(_, mode) = validated.target else { throw ExportError.validatedPublicationRejected }
        switch mode {
        case .selfContained:
            return nil
        case .standalone(style: .linked):
            throw ExportError.validatedPublicationRejected
        case .standalone(style: .embedded):
            guard !validated.resources.isEmpty else { return nil }
        }
        let assetsName = validated.assetsDirectoryName
        guard safeName(assetsName) else { throw ExportError.validatedPublicationRejected }
        if mkdirat(parent.descriptor, assetsName, mode_t(S_IRUSR | S_IWUSR | S_IXUSR)) != 0,
           errno != EEXIST {
            throw posixFailure()
        }
        let descriptor = openat(parent.descriptor, assetsName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ExportError.validatedPublicationRejected }
        let directory = DirectoryHandle(descriptor)
        let stamp = try directoryStamp(descriptor)
        afterOpening?()
        let assetsURL = parentURL.appendingPathComponent(assetsName, isDirectory: true)
        let marker = ExportFileWriter.markerFileName
        var entries = [(name: String, stamp: Stamp)]()
        try entries.append((marker, stage(Data(ExportFileWriter.markerContent.utf8),
                                          named: marker, in: descriptor)))
        var urls = [assetsURL.appendingPathComponent(marker)]
        for resource in validated.resources {
            try Task.checkCancellation()
            try lease.checkActive()
            guard resource.identity == ExportResourceIdentity(
                bytes: resource.bytes, mimeType: resource.identity.mimeType
            ), safeName(resource.identity.fileName) else { throw ExportError.validatedPublicationRejected }
            let name = resource.identity.fileName
            try entries.append((name, stage(resource.bytes, named: name, in: descriptor)))
            urls.append(assetsURL.appendingPathComponent(name))
        }
        return StagedCompanions(directory: directory, stamp: stamp, entries: entries, urls: urls)
    }

    private static func verify(
        _ validated: ValidatedExportHTML, parent: DirectoryHandle,
        parentPath: String, parentStamp: Stamp, staged: StagedCompanions?
    ) throws {
        guard validated.bytesAreIntact(), try directoryAtPath(parentPath, matches: parentStamp)
        else { throw ExportError.validatedPublicationRejected }
        guard let staged else { return }
        guard try childDirectory(validated.assetsDirectoryName, in: parent.descriptor, matches: staged.stamp)
        else { throw ExportError.validatedPublicationRejected }
        for entry in staged.entries {
            guard try childStamp(entry.name, in: staged.directory.descriptor) == entry.stamp
            else { throw ExportError.validatedPublicationRejected }
        }
    }

    private static func safeName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && !name.contains("/") && !name.contains("\0")
    }

    private static func directoryStamp(_ descriptor: Int32) throws -> Stamp {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw posixFailure() }
        let stamp = Stamp(info)
        guard stamp.kind == mode_t(S_IFDIR) else { throw ExportError.validatedPublicationRejected }
        return stamp
    }

    private static func childStamp(_ name: String, in directory: Int32) throws -> Stamp {
        var info = stat()
        guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw posixFailure() }
        return Stamp(info)
    }

    private static func childDirectory(_ name: String, in parent: Int32, matches expected: Stamp) throws -> Bool {
        try childStamp(name, in: parent).sameDirectory(as: expected)
    }

    private static func directoryAtPath(_ path: String, matches expected: Stamp) throws -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else { throw posixFailure() }
        return Stamp(info).sameDirectory(as: expected)
    }

    /// Existing names are opened without following links and compared by bytes.
    /// New names are linked from an exclusive temporary inode, never renamed
    /// over a resource used by the previous primary.
    private static func stage(_ bytes: Data, named name: String, in directory: Int32) throws -> Stamp {
        if let existing = try existingBytes(bytes, named: name, in: directory) {
            return existing
        }
        let temporary = ".mt-\(UUID().uuidString).stage"
        let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                                mode_t(S_IRUSR | S_IWUSR))
        guard descriptor >= 0 else { throw posixFailure() }
        defer {
            _ = Darwin.close(descriptor)
            _ = unlinkat(directory, temporary, 0)
        }
        try writeAll(bytes, to: descriptor)
        guard fsync(descriptor) == 0 else { throw posixFailure() }
        if linkat(directory, temporary, directory, name, 0) != 0,
           errno != EEXIST {
            throw posixFailure()
        }
        // Removing the temporary hard link changes the installed inode's
        // change time. Capture its final stamp only after that mutation.
        guard unlinkat(directory, temporary, 0) == 0 else { throw posixFailure() }
        guard let installed = try existingBytes(bytes, named: name, in: directory)
        else { throw ExportError.validatedPublicationRejected }
        return installed
    }

    private static func existingBytes(_ expected: Data, named name: String, in directory: Int32) throws -> Stamp? {
        // Non-blocking open prevents a substituted FIFO from waiting forever
        // before fstat can reject its non-regular inode.
        let descriptor = openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT {
                return nil
            }
            throw ExportError.validatedPublicationRejected
        }
        defer { _ = Darwin.close(descriptor) }
        var initial = stat()
        guard fstat(descriptor, &initial) == 0 else { throw posixFailure() }
        let stamp = Stamp(initial)
        guard stamp.kind == mode_t(S_IFREG), stamp.size == expected.count
        else { throw ExportError.validatedPublicationRejected }
        var actual = Data()
        actual.reserveCapacity(expected.count)
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while actual.count < expected.count {
            let count = min(buffer.count, expected.count - actual.count)
            let readCount = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, count) }
            if readCount < 0, errno == EINTR {
                continue
            }
            guard readCount > 0 else { throw ExportError.validatedPublicationRejected }
            actual.append(contentsOf: buffer.prefix(readCount))
        }
        var extra: UInt8 = 0
        guard Darwin.read(descriptor, &extra, 1) == 0, actual == expected else {
            throw ExportError.validatedPublicationRejected
        }
        var final = stat()
        guard fstat(descriptor, &final) == 0, Stamp(final) == stamp else {
            throw ExportError.validatedPublicationRejected
        }
        return stamp
    }

    private static func promote(_ bytes: Data, as name: String, in directory: Int32) throws {
        let temporary = ".mt-\(UUID().uuidString).html.tmp"
        let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                                mode_t(S_IRUSR | S_IWUSR))
        guard descriptor >= 0 else { throw posixFailure() }
        defer {
            _ = Darwin.close(descriptor)
            _ = unlinkat(directory, temporary, 0)
        }
        try writeAll(bytes, to: descriptor)
        guard fsync(descriptor) == 0 else { throw posixFailure() }
        guard renameat(directory, temporary, directory, name) == 0 else { throw posixFailure() }
    }

    private static func writeAll(_ bytes: Data, to descriptor: Int32) throws {
        try bytes.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, baseAddress.advanced(by: offset), buffer.count - offset)
                if written < 0, errno == EINTR {
                    continue
                }
                guard written > 0 else { throw posixFailure() }
                offset += written
            }
        }
    }

    private static func posixFailure() -> ExportError {
        .writeFailed(underlying: NSError(domain: NSPOSIXErrorDomain, code: Int(errno)))
    }
}
