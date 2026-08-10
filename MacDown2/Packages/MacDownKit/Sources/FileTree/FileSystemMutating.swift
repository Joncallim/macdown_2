import Darwin
import Foundation

public protocol FileSystemMutating: Sendable {
    func itemKind(at url: URL) async throws -> FileSystemItemKind?
    func createFile(at url: URL) async throws
    func createDirectory(at url: URL) async throws
    func move(from source: URL, to destination: URL) async throws
    func copy(from source: URL, to destination: URL) async throws
    func trash(at url: URL) async throws
}

public enum FileSystemItemKind: Sendable, Equatable {
    case file
    case directory
}

public struct FileSystemMutator: FileSystemMutating {
    public init() {}
    public func itemKind(at url: URL) async throws -> FileSystemItemKind? {
        await Task<FileSystemItemKind?, Never>.detached {
            var info = stat()
            guard Darwin.lstat(url.path, &info) == 0 else { return nil }
            if (info.st_mode & S_IFMT) == S_IFDIR {
                return .directory
            }
            guard (info.st_mode & S_IFMT) == S_IFLNK else { return .file }
            var targetIsDirectory = ObjCBool(false)
            let targetExists = FileManager.default.fileExists(atPath: url.path, isDirectory: &targetIsDirectory)
            return targetExists && targetIsDirectory.boolValue ? .directory : .file
        }.value
    }

    public func createFile(at url: URL) async throws {
        try await Task.detached {
            let descriptor = Darwin.open(url.path, O_CREAT | O_EXCL | O_WRONLY, 0o666)
            guard descriptor >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            _ = Darwin.close(descriptor)
        }.value
    }

    public func createDirectory(at url: URL) async throws {
        try await Task.detached {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: false
            )
        }.value
    }

    public func move(from source: URL, to destination: URL) async throws {
        try await Task.detached {
            try FileManager.default.moveItem(at: source, to: destination)
        }.value
    }

    public func copy(from source: URL, to destination: URL) async throws {
        try await Task.detached {
            try FileManager.default.copyItem(at: source, to: destination)
        }.value
    }

    public func trash(at url: URL) async throws {
        try await Task.detached {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }.value
    }
}
