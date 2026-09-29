import Foundation

/// What loading the snippet file found.
public enum SnippetLoadResult: Sendable, Equatable {
    /// No snippet file yet — the normal first-run state.
    case missing
    case loaded(SnippetLibrary)
    /// The file exists but is not a snippet library this build can read. It is
    /// left untouched on disk (never overwritten by a load).
    case unreadable
    /// The file was written by a newer version.
    case unsupportedVersion(Int)

    /// The snippets to offer: the library's, or none when there is no usable file.
    public var snippets: [Snippet] {
        if case let .loaded(library) = self {
            library.snippets
        } else {
            []
        }
    }
}

/// Versioned JSON snippet file in Application Support, written atomically —
/// the same shape as `WorkspaceSessionStore`. Holds data only: nothing in the
/// file is ever executed or shell-expanded.
public struct SnippetStore: Sendable {
    public static let defaultFileName = "snippets.json"

    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? FileManager.default.temporaryDirectory
            self.fileURL = appSupport
                .appendingPathComponent("MacDown 2", isDirectory: true)
                .appendingPathComponent(Self.defaultFileName)
        }
    }

    public func load() -> SnippetLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .missing }
        guard let data = try? Data(contentsOf: fileURL) else { return .unreadable }
        guard let library = try? JSONDecoder().decode(SnippetLibrary.self, from: data) else { return .unreadable }
        guard library.version == SnippetLibrary.currentVersion else { return .unsupportedVersion(library.version) }
        return .loaded(library)
    }

    /// Writes `library` atomically (temp file + rename), creating the
    /// directory if needed.
    public func save(_ library: SnippetLibrary) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: fileURL, options: .atomic)
    }

    /// Creates an empty snippet file when — and only when — none exists, so
    /// "Edit Snippets…" has something to open without ever clobbering a file
    /// the user (or a newer version) wrote. Returns whether a file now exists.
    @discardableResult
    public func createIfMissing() -> Bool {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return true
        }
        return (try? save(SnippetLibrary())) != nil
    }
}
