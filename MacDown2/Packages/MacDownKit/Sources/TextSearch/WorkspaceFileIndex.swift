import FileCore
import Foundation

/// One indexed path under a workspace root — the fixed record
/// `WorkspaceFileIndex` snapshots and `FuzzyPathScore` ranks against.
public struct IndexedPath: Sendable, Equatable, Hashable {
    /// Root-relative path, `/`-separated, no leading slash.
    public let relativePath: String
    public let basename: String
    /// Folded and decomposed once at construction (index-build time, which
    /// happens far less often than every Quick Open keystroke), not
    /// recomputed on every `query(_:)` call — see
    /// `FuzzyPathScore.score(foldedQuery:foldedPath:foldedBasename:)`'s own
    /// doc comment for the 100k-path performance finding this avoids.
    let foldedRelativePath: FuzzyPathScore.FoldedText
    let foldedBasename: FuzzyPathScore.FoldedText

    public init(relativePath: String, basename: String) {
        self.relativePath = relativePath
        self.basename = basename
        foldedRelativePath = FuzzyPathScore.FoldedText(relativePath)
        foldedBasename = FuzzyPathScore.FoldedText(basename)
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
    /// Inverted index: ASCII byte value -> ascending indices into `paths`
    /// whose folded basename or relative path contains that byte anywhere.
    /// Built once whenever `paths` changes (index-build time), not on every
    /// `query(_:)` call — see `query`'s own doc comment for why a per-byte
    /// postings list, not just `FoldedText.asciiMask`'s own O(1)-per-candidate
    /// reject, was needed to meet the 100k-path budget (issue #112).
    private var postingsByASCIIByte: [UInt8: [Int]] = [:]
    private var generation = 0
    private var currentWalkTask: Task<[IndexedPath], Never>?
    private let walk: @Sendable (URL, Set<String>) -> [IndexedPath]

    public init() {
        walk = { root, excludedDirectoryNames in
            DirectoryWalker().walk(root: root, excludedDirectoryNames: excludedDirectoryNames)
        }
    }

    /// Test-only seam (package-internal, not part of the public API):
    /// substitutes the real `DirectoryWalker` with a caller-controlled
    /// closure, matching `DocumentFileMonitor`'s own established
    /// injectable-dependency shape for testing actor-based async work
    /// deterministically. Used to prove `rebuild` genuinely surfaces
    /// `.building` while a walk is in flight without depending on real
    /// disk-I/O timing being slow enough to observe -- a wall-clock race
    /// would be exactly the kind of non-deterministic test this project's
    /// own `RELEASE_HARDENING.md` §12 rules out.
    init(walk: @escaping @Sendable (URL, Set<String>) -> [IndexedPath]) {
        self.walk = walk
    }

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
        let walk = walk
        let task = Task.detached(priority: .utility) {
            walk(root, excludedDirectoryNames)
        }
        currentWalkTask = task
        let result = await task.value
        guard currentGeneration == generation else { return } // superseded by a newer rebuild
        setPaths(result)
        state = .ready(count: result.count)
    }

    /// Discards the current snapshot and returns to `.empty` -- for when the
    /// workspace root closes (no folder open), so a stale snapshot from a
    /// previously-open folder can never leak into a later query against an
    /// empty workspace. Cancels any in-flight rebuild the same way a
    /// superseding `rebuild(root:)` would (EPIC-22 §6.15, Slice 6a).
    public func clear() {
        generation += 1
        currentWalkTask?.cancel()
        currentWalkTask = nil
        setPaths([])
        state = .empty
    }

    /// Ranked matches for `query`, capped at `limit`. Never touches disk —
    /// operates entirely on the last-built in-memory snapshot, so a
    /// keystroke never triggers a new traversal (the epic's explicit
    /// "Quick Open queries an in-memory snapshot" requirement).
    ///
    /// Scans only `candidateIndices(for:)`'s own postings-list result, not
    /// every one of `paths` — see that method's own doc comment. Folds/
    /// decomposes `query` exactly ONCE for the whole call, then reuses each
    /// candidate's own precomputed `foldedRelativePath`/`foldedBasename` --
    /// see `FuzzyPathScore.score(foldedQuery:foldedPath:foldedBasename:)`'s
    /// own doc comment for why the naive per-path-redo-everything approach,
    /// even after adding the postings filter, would still miss the 100k-path
    /// budget (issue #112) by a wide margin.
    ///
    /// `recentRelativePaths` implements issue #112's "Recent-file history
    /// feeds Quick Open ranking": a small, tier-safe (see
    /// `recentFileBonus`'s own doc comment) bonus applied to any candidate
    /// whose `relativePath` is in the set, so it wins ties against an
    /// otherwise-equal-tier match rather than reordering across tiers.
    /// `TextSearch` has no knowledge of "recent files" as its own concept —
    /// per `FuzzyPathScore`'s own doc comment, the caller (`QuickOpenModel`)
    /// computes this plain set of strings and passes it in fresh each call,
    /// the same way `rebuild(root:)` takes an external `URL` without
    /// depending on `FileTreeModel` itself.
    public func query(_ query: String, limit: Int = 100, recentRelativePaths: Set<String> = []) -> [IndexedPath] {
        guard !query.isEmpty else { return Array(paths.prefix(limit)) }
        let foldedQuery = FuzzyPathScore.FoldedText(query)
        let candidates = candidateIndices(for: foldedQuery)
        var scored: [(path: IndexedPath, score: Double)] = []
        scored.reserveCapacity(candidates.count)
        for index in candidates {
            let path = paths[index]
            guard let score = FuzzyPathScore.score(
                foldedQuery: foldedQuery,
                foldedPath: path.foldedRelativePath,
                foldedBasename: path.foldedBasename
            ) else {
                continue
            }
            let bonus = recentRelativePaths.contains(path.relativePath) ? Self.recentFileBonus : 0
            scored.append((path, score + bonus))
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.path.relativePath < $1.path.relativePath }
            .prefix(limit)
            .map(\.path)
    }

    /// Every gap between `FuzzyPathScore`'s own tiers (exact 1000, prefix
    /// 900, basename-fuzzy (500, 599], path-fuzzy (0, 99]) is at least 100,
    /// so adding this to any one candidate's score can never lift it into
    /// the next tier up — it only ever breaks a tie within the tier its
    /// underlying match quality already earned.
    private static let recentFileBonus: Double = 10

    /// Indices into `paths` that could possibly fuzzy-match `foldedQuery`,
    /// using `postingsByASCIIByte` to avoid ever visiting the full `paths`
    /// array at query time. Every genuine match must appear in EVERY one of
    /// the query's own distinct ASCII characters' postings lists (a
    /// necessary, not sufficient, condition — `FuzzyPathScore.score` itself
    /// still runs against each returned index to confirm an actual match),
    /// so this intersects all of them, not just the single rarest one:
    /// picking only the rarest character alone was found, under adversarial
    /// review, to still occasionally miss the 100k-path budget (issue #112)
    /// when that "rarest" character wasn't rare enough on its own — the
    /// full intersection is both correct (still a superset of every real
    /// match, by the same reasoning) and meaningfully smaller in practice.
    /// Sorts postings lists smallest-first before intersecting (the
    /// standard multi-way set-intersection optimization) so the result
    /// shrinks as early as possible and a query with any one truly rare
    /// character short-circuits to empty immediately. A non-ASCII-only
    /// query (no ASCII character to build a postings intersection from)
    /// falls back to every index, matching `query`'s own pre-postings
    /// behavior for that rare case.
    private func candidateIndices(for foldedQuery: FuzzyPathScore.FoldedText) -> [Int] {
        var buckets: [[Int]] = []
        var seenBytes: Set<UInt8> = []
        for scalar in foldedQuery.scalars where scalar.isASCII {
            let byte = UInt8(scalar.value)
            guard seenBytes.insert(byte).inserted else { continue }
            buckets.append(postingsByASCIIByte[byte] ?? [])
        }
        guard !buckets.isEmpty else { return Array(paths.indices) }
        buckets.sort { $0.count < $1.count }
        var intersected = buckets[0]
        for bucket in buckets.dropFirst() where !intersected.isEmpty {
            intersected = Self.intersectSortedAscending(intersected, bucket)
        }
        return intersected
    }

    /// Merge-based intersection of two ascending, duplicate-free index
    /// arrays — both always are, since `setPaths` appends each path's index
    /// to a given byte's postings list at most once, in ascending
    /// enumeration order.
    private static func intersectSortedAscending(_ first: [Int], _ second: [Int]) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(min(first.count, second.count))
        var firstIndex = first.startIndex
        var secondIndex = second.startIndex
        while firstIndex < first.count, secondIndex < second.count {
            if first[firstIndex] == second[secondIndex] {
                result.append(first[firstIndex])
                firstIndex += 1
                secondIndex += 1
            } else if first[firstIndex] < second[secondIndex] {
                firstIndex += 1
            } else {
                secondIndex += 1
            }
        }
        return result
    }

    /// Replaces `paths` and rebuilds `postingsByASCIIByte` to match —
    /// callers are responsible for setting `state` themselves afterward,
    /// since `.ready(count:)` (a real rebuild/seed) and `.empty` (`clear()`)
    /// mean different things this helper has no way to infer from `paths`
    /// alone (an empty root is `.empty`, not `.ready(count: 0)`).
    private func setPaths(_ newPaths: [IndexedPath]) {
        paths = newPaths
        var postings: [UInt8: [Int]] = [:]
        for (index, path) in newPaths.enumerated() {
            var seenBytes: Set<UInt8> = []
            for scalar in path.foldedBasename.scalars where scalar.isASCII {
                let byte = UInt8(scalar.value)
                if seenBytes.insert(byte).inserted {
                    postings[byte, default: []].append(index)
                }
            }
            for scalar in path.foldedRelativePath.scalars where scalar.isASCII {
                let byte = UInt8(scalar.value)
                if seenBytes.insert(byte).inserted {
                    postings[byte, default: []].append(index)
                }
            }
        }
        postingsByASCIIByte = postings
    }

    /// Test-only seam (package-internal, not part of the public API):
    /// installs a synthetic path list directly and marks the index
    /// `.ready`, bypassing `rebuild`'s real directory walk entirely. Lets
    /// the 100k-path query-performance budget (EPIC-22 §11) be measured
    /// without needing 100k real files on disk — `rebuild`'s own existing
    /// tests, against real (much smaller) trees, already cover directory-walk
    /// correctness; this seam isolates `query`'s own in-memory cost, the
    /// thing the budget is actually about (a Quick Open keystroke never
    /// touches disk — see `query`'s own doc comment).
    func seedForTesting(_ paths: [IndexedPath]) {
        generation += 1
        currentWalkTask?.cancel()
        currentWalkTask = nil
        setPaths(paths)
        state = .ready(count: paths.count)
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
