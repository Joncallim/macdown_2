import Foundation

/// Which indexed paths a folder search considers, distinct from
/// `FileTree`'s own `FileTreeFilter` (a sidebar-listing concern — hidden
/// files, supported-extensions-only, folders-first — not a search-scoping
/// one). Directory-level exclusion (`.git`, `.build`, `node_modules`, etc.)
/// already happened once, when `WorkspaceFileIndex` built its snapshot
/// (`WorkspaceFileIndex.defaultExcludedDirectoryNames`); this type does not
/// repeat that decision, only narrows further within what the index already
/// knows about.
///
/// Binary/non-decodable files are always skipped and counted, unconditionally
/// — this is not a stored flag on this filter, deliberately: MacDown 2's
/// folder search has no byte-level search path to fall back to (it searches
/// `FileStore`-decoded `String` content only, via
/// `WorkspaceSearchEngine.search`), so a toggle with only one implementable
/// value would be dead configuration surface rather than a real choice. See
/// `WorkspaceSearchEngineTests.aBinaryFileIsSkippedAndCountedRatherThanCrashingOrBeingSearched`
/// for that policy's own coverage.
public struct FolderSearchFilter: Sendable, Equatable {
    /// Glob-style patterns (see `GlobPattern`) a path must match at least
    /// one of to be searched. `nil` (the default) means "search every
    /// indexed file" — distinct from an empty array, which would mean
    /// "match nothing." A pattern containing no `/` matches against the
    /// file's own basename, anywhere in the tree (e.g. `*.md` matches both
    /// `README.md` and `docs/guide.md`); a pattern containing `/` matches
    /// the full root-relative path instead (e.g. `docs/**/*.md`).
    public var includeGlobs: [String]?
    /// Glob-style patterns a path must not match any of. Exclude always
    /// takes precedence over include: a path matching both an include and
    /// an exclude pattern is excluded — issue #112's "include/exclude glob
    /// filters," using the same exclude-wins precedence every comparable
    /// tool (`.gitignore`, ripgrep, VS Code search) already uses, rather
    /// than inventing a third, surprising rule.
    public var excludeGlobs: [String]
    /// Whether hidden files/directories are included (issue #112's
    /// "hidden-file toggle"). `false` by default, matching Quick Open's own
    /// permanent behavior. `WorkspaceFileIndex` always walks and tags hidden
    /// entries (`IndexedPath.isHidden`) regardless of this flag, so toggling
    /// it costs no second directory walk — `WorkspaceSearchEngine.search`
    /// reads this value once, up front, via
    /// `WorkspaceFileIndex.allPaths(includeHidden:)`.
    public var includeHidden: Bool

    public init(
        includeGlobs: [String]? = nil,
        excludeGlobs: [String] = [],
        includeHidden: Bool = false
    ) {
        self.includeGlobs = includeGlobs
        self.excludeGlobs = excludeGlobs
        self.includeHidden = includeHidden
    }

    func matches(_ path: IndexedPath) -> Bool {
        if let includeGlobs, !includeGlobs.contains(where: { Self.matchesGlob($0, path: path) }) {
            return false
        }
        guard !excludeGlobs.contains(where: { Self.matchesGlob($0, path: path) }) else { return false }
        return true
    }

    private static func matchesGlob(_ pattern: String, path: IndexedPath) -> Bool {
        let target = pattern.contains("/") ? path.relativePath : path.basename
        return GlobPattern.matches(pattern: pattern, text: target)
    }
}
