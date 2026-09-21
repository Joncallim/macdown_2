import FileCore
import Foundation

/// One indexed path under a workspace root — the fixed record
/// `WorkspaceFileIndex` snapshots and `FuzzyPathScore` ranks against.
public struct IndexedPath: Sendable, Equatable, Hashable {
    /// Root-relative path, `/`-separated, no leading slash.
    public let relativePath: String
    public let basename: String

    public init(relativePath: String, basename: String) {
        self.relativePath = relativePath
        self.basename = basename
    }
}

/// Builds and holds an in-memory snapshot of every regular file under one
/// workspace root, for Quick Open's fuzzy lookup. Recursive traversal is
/// genuinely new in this codebase (`FileTree`'s own traversal is
/// single-level and lazy, expand-on-click only — see
/// `planning/epic-22-implementation.md` §2.1) and must not be confused with
/// or duplicate `FileTree`'s sidebar model.
///
/// An `actor` because building/rebuilding is a genuine, potentially
/// long-running background operation (target: off-main, visible progress/
/// ready state, per the epic's performance budgets) whose result must be
/// safely queryable while a rebuild is in flight.
public actor WorkspaceFileIndex {
    public enum State: Sendable, Equatable {
        case empty
        case building
        case ready(count: Int)
        case failed(String)
    }

    public private(set) var state: State = .empty
    private var paths: [IndexedPath] = []
    private var generation = 0
    private var currentWalkTask: Task<[IndexedPath], Never>?

    public init() {}

    /// Rebuilds the index from `root`, discarding any previous snapshot
    /// only once the new one is ready (a query made while a rebuild is in
    /// flight still sees the last-good snapshot, never a half-built one —
    /// matching `FileTreeModel`'s own "stale generation" discipline).
    ///
    /// A rebuild that supersedes an in-flight one cancels it, so rapid
    /// repeated calls (e.g. fast workspace-root switching) don't pile up
    /// concurrent full directory walks; `DirectoryWalker.walk` checks
    /// `Task.isCancelled` between entries so a cancelled walk actually stops
    /// promptly rather than merely having its result discarded.
    public func rebuild(root: URL,
                        excluding excludedDirectoryNames: Set<String> = defaultExcludedDirectoryNames) async {
        generation += 1
        let currentGeneration = generation
        state = .building
        currentWalkTask?.cancel()
        let walker = DirectoryWalker()
        let task = Task.detached(priority: .utility) {
            walker.walk(root: root, excludedDirectoryNames: excludedDirectoryNames)
        }
        currentWalkTask = task
        let result = await task.value
        guard currentGeneration == generation else { return } // superseded by a newer rebuild
        paths = result
        state = .ready(count: result.count)
    }

    /// Ranked matches for `query`, capped at `limit`. Never touches disk —
    /// operates entirely on the last-built in-memory snapshot, so a
    /// keystroke never triggers a new traversal (the epic's explicit
    /// "Quick Open queries an in-memory snapshot" requirement).
    public func query(_ query: String, limit: Int = 100) -> [IndexedPath] {
        guard !query.isEmpty else { return Array(paths.prefix(limit)) }
        let scored: [(path: IndexedPath, score: Double)] = paths.compactMap { path in
            guard let score = FuzzyPathScore.score(query: query, path: path.relativePath, basename: path.basename)
            else {
                return nil
            }
            return (path, score)
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.path.relativePath < $1.path.relativePath }
            .prefix(limit)
            .map(\.path)
    }

    /// Directory names never worth indexing — build output, VCS metadata,
    /// dependency caches. Mirrors the kind of exclusion any workspace
    /// indexer needs; not a `FileTree` sidebar concern (the sidebar shows
    /// these if the user expands into them; Quick Open should not surface
    /// thousands of build artefacts by default).
    public static let defaultExcludedDirectoryNames: Set<String> = [
        ".git", ".build", ".swiftpm", "node_modules", "DerivedData", ".DS_Store",
    ]
}

/// The recursive walk itself, isolated from the actor so it can run inside
/// `Task.detached` without capturing actor state, and so its symlink-loop
/// safety (new; `FileTree`'s own traversal is single-level/lazy and has no
/// equivalent guard — see `planning/epic-22-implementation.md` §2.1) is
/// independently testable.
///
/// Deliberately does not depend on `FileTree`'s `DirectoryReading`/
/// `FileSystemDirectoryReader`/`DirectoryEntry` (single-level-listing types
/// designed for the sidebar's lazy, expand-on-click model) — `TextSearch`
/// depends only on `FileCore` + Foundation (architecture doc §5.1), so this
/// is a small, deliberate, local duplication of "list one directory's
/// entries with the resource keys a recursive walk needs," not a shared
/// primitive.
struct DirectoryWalker: Sendable {
    func walk(root: URL, excludedDirectoryNames: Set<String>) -> [IndexedPath] {
        var results: [IndexedPath] = []
        var visitedDirectoryIdentities: Set<PhysicalFileIdentity.FileObjectID> = []
        walk(
            directory: root.standardizedFileURL,
            relativeTo: root.standardizedFileURL,
            excludedDirectoryNames: excludedDirectoryNames,
            visited: &visitedDirectoryIdentities,
            into: &results
        )
        return results
    }

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isHiddenKey,
        .isPackageKey,
        .isSymbolicLinkKey,
    ]

    private func walk(
        directory: URL,
        relativeTo root: URL,
        excludedDirectoryNames: Set<String>,
        visited: inout Set<PhysicalFileIdentity.FileObjectID>,
        into results: inout [IndexedPath]
    ) {
        guard !Task.isCancelled else { return }
        guard let identity = PhysicalFileIdentity(url: directory).fileObjectID else { return }
        guard visited.insert(identity).inserted else { return } // symlink loop guard
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory.resolvingSymlinksInPath(),
            includingPropertiesForKeys: Array(Self.resourceKeys),
            options: []
        ) else { return }

        for child in children {
            guard !Task.isCancelled else { return }
            guard let values = try? child.resourceValues(forKeys: Self.resourceKeys) else { continue }
            guard values.isHidden != true else { continue }
            let name = child.lastPathComponent
            // Resource values describe the link itself on some file
            // systems, so a symlink to a directory can report
            // `isDirectory == false` when queried unresolved — mirrors
            // `FileSystemDirectoryReader.contents(of:)`'s existing
            // resolve-and-recheck for symlinks (`DirectoryReading.swift`),
            // without which a symlinked directory would be misclassified as
            // a file and its subtree silently dropped from the index.
            let isSymbolicLink = values.isSymbolicLink == true
            let targetValues = isSymbolicLink
                ? try? child.resolvingSymlinksInPath().resourceValues(forKeys: Self.resourceKeys)
                : nil
            let isDirectory = values.isDirectory == true || targetValues?.isDirectory == true
            let isPackage = values.isPackage == true || targetValues?.isPackage == true
            // Rebind to the lexical parent so a symlinked root's children
            // keep the user-facing path, matching `FileTree`'s own
            // lexical-parent convention (`DirectoryReading.swift`).
            let lexicalChild = directory.appendingPathComponent(name, isDirectory: isDirectory)
            if isDirectory, !isPackage {
                guard !excludedDirectoryNames.contains(name) else { continue }
                walk(
                    directory: lexicalChild,
                    relativeTo: root,
                    excludedDirectoryNames: excludedDirectoryNames,
                    visited: &visited,
                    into: &results
                )
            } else {
                results.append(IndexedPath(
                    relativePath: relativePath(of: lexicalChild, relativeTo: root),
                    basename: name
                ))
            }
        }
    }

    private func relativePath(of url: URL, relativeTo root: URL) -> String {
        let rootComponents = root.pathComponents
        let components = url.pathComponents
        guard components.count > rootComponents.count else { return url.lastPathComponent }
        return components[rootComponents.count...].joined(separator: "/")
    }
}
