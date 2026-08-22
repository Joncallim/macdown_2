import FileCore
import Foundation

public enum FileTreeOperationError: Error, Sendable, Equatable, LocalizedError {
    case nameEmpty
    case nameContainsPathSeparator
    case nameExists(String)
    case sourceMissing
    case destinationNotDirectory
    case outsideCurrentRoot
    case staleOperation
    case moveIntoOwnSubtree
    case posix(Int32)
    case underlying(String)

    public var errorDescription: String? {
        switch self {
        case .nameEmpty: "A name is required."
        case .nameContainsPathSeparator: "Names cannot contain / or :."
        case let .nameExists(name): "\"\(name)\" already exists."
        case .sourceMissing: "The item no longer exists."
        case .destinationNotDirectory: "The destination is not a folder."
        case .outsideCurrentRoot: "The destination is outside the open folder."
        case .staleOperation: "The folder changed before the operation could start."
        case .moveIntoOwnSubtree: "A folder cannot be moved into itself."
        case let .posix(code): "Folder operation failed (POSIX error \(code))."
        case let .underlying(message): message
        }
    }
}

/// A caller captures this synchronously, before scheduling a CRUD task. Its
/// generation makes an A → B → A root replacement distinct from the original A.
public struct FileTreeOperationContext: Sendable, Equatable {
    let root: URL?
    let generation: UInt
}

public struct FileTreeOperationResult: Sendable, Equatable {
    public let url: URL
    public let isCurrent: Bool

    public init(url: URL, isCurrent: Bool) {
        self.url = url
        self.isCurrent = isCurrent
    }
}

public enum FileTreeNaming {
    public static func uniqueName(base: String, extension ext: String, existing: Set<String>) -> String {
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        let folded = Set(existing.map(foldedName))
        var index = 1
        while true {
            let name = index == 1 ? "\(base)\(suffix)" : "\(base) \(index)\(suffix)"
            if !folded.contains(foldedName(name)) {
                return name
            }
            index += 1
        }
    }

    private static func foldedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    public static func duplicateName(of name: String, existing: Set<String>) -> String {
        let url = URL(fileURLWithPath: name)
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        let folded = Set(existing.map(foldedName))
        var index = 1
        while true {
            let candidate = index == 1 ? "\(stem) copy\(suffix)" : "\(stem) copy \(index)\(suffix)"
            if !folded.contains(foldedName(candidate)) {
                return candidate
            }
            index += 1
        }
    }

    public static func validate(
        _ name: String,
        existing: Set<String>,
        currentName: String?
    ) -> FileTreeOperationError? {
        guard !name.isEmpty else { return .nameEmpty }
        guard !name.contains("/"), !name.contains(":") else { return .nameContainsPathSeparator }
        let names = existing.filter { candidate in candidate != currentName }
        return names.contains { $0.caseInsensitiveCompare(name) == .orderedSame } ? .nameExists(name) : nil
    }
}

public enum FileTreeMoveValidation {
    /// Path-COMPONENT containment, not string prefix (D10). Part of the
    /// documented public API contract (`planning/epic-09-implementation.md`
    /// §4.2) even though the model's own `move()` uses the stronger,
    /// symlink-aware `FileTreeCopySafety.validateDirectoryCopy` internally —
    /// this lexical check is the one package clients are specified to call.
    public static func validate(source: URL, intoDirectory destination: URL) -> FileTreeOperationError? {
        let sourceComponents = source.standardizedFileURL.pathComponents
        let destinationComponents = destination.standardizedFileURL.pathComponents
        if destinationComponents.starts(with: sourceComponents) {
            return .moveIntoOwnSubtree
        }
        return nil
    }
}

public enum FileTreeCopySafety {
    public static func validateDirectoryCopy(
        source: URL,
        intoDirectory destination: URL
    ) throws -> FileTreeOperationError? {
        let sourceID = try identity(of: source)
        var ancestor = destination.resolvingSymlinksInPath().standardizedFileURL
        while true {
            if try identity(of: ancestor) == sourceID {
                return .moveIntoOwnSubtree
            }
            if ancestor.path == "/" {
                return nil
            }
            let parent = ancestor.deletingLastPathComponent()
            guard parent.path != ancestor.path else { return nil }
            ancestor = parent
        }
    }

    private static func identity(of url: URL) throws -> PhysicalFileIdentity.FileObjectID {
        guard let identity = PhysicalFileIdentity(url: url).fileObjectID else {
            throw POSIXError(.ENOENT)
        }
        return identity
    }
}
