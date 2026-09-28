import Foundation

/// Which indexed paths a folder search considers, distinct from
/// `FileTree`'s own `FileTreeFilter` (a sidebar-listing concern — hidden
/// files, supported-extensions-only, folders-first — not a search-scoping
/// one). Directory-level exclusion (`.git`, `.build`, `node_modules`, etc.)
/// already happened once, when `WorkspaceFileIndex` built its snapshot
/// (`WorkspaceFileIndex.defaultExcludedDirectoryNames`); this type does not
/// repeat that decision, only narrows further within what the index already
/// knows about.
public struct FolderSearchFilter: Sendable, Equatable {
    /// File extensions (lowercase, no leading dot) to search. `nil` (the
    /// default) searches every indexed file regardless of extension.
    public var includedExtensions: Set<String>?

    public init(includedExtensions: Set<String>? = nil) {
        self.includedExtensions = includedExtensions
    }

    func matches(_ path: IndexedPath) -> Bool {
        guard let includedExtensions else { return true }
        // `NSString.pathExtension`, not a hand-rolled `lastIndex(of: ".")`
        // split: the latter would treat a leading-dot name's own dot as an
        // extension separator (e.g. ".gitignore" -> "gitignore"), which
        // Foundation's own convention correctly does not. Not reachable
        // today (`DirectoryWalker` already excludes every hidden/dotfile
        // entry before it reaches the index), but matching the platform's
        // own semantics here costs nothing and removes the inconsistency
        // outright rather than leaving it for whoever next reuses this
        // filter against a different, unfiltered path source.
        let extensionValue = (path.basename as NSString).pathExtension.lowercased()
        guard !extensionValue.isEmpty else { return false }
        return includedExtensions.contains(extensionValue)
    }
}
