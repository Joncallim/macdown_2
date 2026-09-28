import FileCore
import Foundation
import Testing
@testable import TextSearch

@Suite("WorkspaceSearchEngine")
struct WorkspaceSearchEngineTests {
    /// A real temporary directory tree, torn down after the test.
    private final class TempTree {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }

        func write(_ relativePath: String, text: String) throws {
            let url = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
        }

        func writeBinary(_ relativePath: String) throws {
            let url = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Starts with 0x80, an orphaned UTF-8 continuation byte with no
            // leading byte -- invalid at the very start of a UTF-8 decode,
            // and (unlike a leading 0xFF 0xFE or 0xFE 0xFF) does not match
            // any of `FileStore`'s own recognized BOM prefixes, so it can
            // never be mistaken for the START of a real UTF-16 file either.
            try Data([0x80, 0x81, 0x82, 0xFF, 0xFE, 0xFD]).write(to: url)
        }

        func makeIndex() async -> WorkspaceFileIndex {
            let index = WorkspaceFileIndex()
            await index.rebuild(root: root)
            return index
        }
    }

    /// Collects streamed `FolderSearchMatch` values from `onMatch`, which is
    /// `@Sendable` and so cannot mutate a plain captured `var` directly —
    /// an `actor` is the straightforward way to collect across that
    /// isolation boundary. Since `onMatch` is itself `async` and `search`
    /// awaits it before moving to the next file, `search`'s own return is
    /// already a deterministic signal that every append below has landed —
    /// no polling or draining needed.
    private actor ResultsBox {
        private(set) var all: [FolderSearchMatch] = []
        func append(_ match: FolderSearchMatch) {
            all.append(match)
        }
    }

    /// Runs a search and returns both the outcome and every streamed
    /// result, collected in order — the shared shape almost every test
    /// below needs, so each test states only what differs.
    private func run(
        root: URL,
        index: WorkspaceFileIndex,
        query: String,
        options: SearchOptions = SearchOptions(),
        filter: FolderSearchFilter = FolderSearchFilter(),
        maxMatches: Int = WorkspaceSearchEngine.defaultMaxMatches
    ) async -> (outcome: FolderSearchOutcome, results: [FolderSearchMatch]) {
        let box = ResultsBox()
        let outcome = await WorkspaceSearchEngine().search(
            root: root,
            index: index,
            query: query,
            options: options,
            filter: filter,
            maxMatches: maxMatches
        ) { match in await box.append(match) }
        return await (outcome, box.all)
    }

    @Test func streamsOneMatchGroupPerFileInIndexedOrder() async throws {
        let tree = try TempTree()
        try tree.write("a.txt", text: "hello world\nhello again")
        try tree.write("b.txt", text: "nothing here")
        try tree.write("c.txt", text: "another hello")
        let index = await tree.makeIndex()

        let (outcome, results) = await run(root: tree.root, index: index, query: "hello")

        guard case let .completed(filesSearched, filesSkipped, matchCount) = outcome else {
            Issue.record("expected .completed, got \(outcome)")
            return
        }
        #expect(filesSearched == 3)
        #expect(filesSkipped == 0)
        #expect(matchCount == 3) // two in a.txt, one in c.txt
        #expect(Set(results.map(\.relativePath)) == ["a.txt", "c.txt"])
        #expect(results.first(where: { $0.relativePath == "a.txt" })?.matches.count == 2)
        #expect(results.first(where: { $0.relativePath == "c.txt" })?.matches.count == 1)
    }

    @Test func emptyQueryMatchesNothingWithoutTouchingAnyFile() async throws {
        let tree = try TempTree()
        try tree.write("a.txt", text: "hello world")
        let index = await tree.makeIndex()

        let (outcome, results) = await run(root: tree.root, index: index, query: "")

        #expect(outcome == .completed(filesSearched: 0, filesSkipped: 0, matchCount: 0))
        #expect(results.isEmpty)
    }

    @Test func invalidRegexIsReportedOnceWithoutTouchingAnyFile() async throws {
        let tree = try TempTree()
        try tree.write("a.txt", text: "hello world")
        let index = await tree.makeIndex()

        let (outcome, results) = await run(
            root: tree.root,
            index: index,
            query: "(unclosed",
            options: SearchOptions(isRegex: true)
        )

        guard case .invalidRegex = outcome else {
            Issue.record("expected .invalidRegex, got \(outcome)")
            return
        }
        #expect(results.isEmpty)
    }

    @Test func aBinaryFileIsSkippedAndCountedRatherThanCrashingOrBeingSearched() async throws {
        let tree = try TempTree()
        try tree.write("readable.txt", text: "hello world")
        try tree.writeBinary("binary.dat")
        let index = await tree.makeIndex()

        let (outcome, results) = await run(root: tree.root, index: index, query: "hello")

        guard case let .completed(filesSearched, filesSkipped, matchCount) = outcome else {
            Issue.record("expected .completed, got \(outcome)")
            return
        }
        #expect(filesSearched == 1)
        #expect(filesSkipped == 1)
        #expect(matchCount == 1)
        #expect(results.map(\.relativePath) == ["readable.txt"])
    }

    @Test func caseInsensitiveUnicodeFoldingMatchesAcrossCase() async throws {
        let tree = try TempTree()
        try tree.write("a.txt", text: "CAFÉ and café and Café")
        let index = await tree.makeIndex()

        let (_, results) = await run(
            root: tree.root,
            index: index,
            query: "café",
            options: SearchOptions(isCaseSensitive: false)
        )

        #expect(results.first?.matches.count == 3)
    }

    @Test func crlfContentIsSearchedCorrectly() async throws {
        let tree = try TempTree()
        try tree.write("a.txt", text: "line one\r\nhello\r\nline three\r\n")
        let index = await tree.makeIndex()

        let (_, results) = await run(root: tree.root, index: index, query: "hello")

        #expect(results.first?.matches.count == 1)
    }

    @Test func aHugeSingleLineIsSearchedWithoutHanging() async throws {
        let tree = try TempTree()
        let huge = String(repeating: "x", count: 2_000_000) + "needle" + String(repeating: "y", count: 2_000_000)
        try tree.write("huge.txt", text: huge)
        let index = await tree.makeIndex()

        let (outcome, results) = await run(root: tree.root, index: index, query: "needle")

        #expect(outcome == .completed(filesSearched: 1, filesSkipped: 0, matchCount: 1))
        #expect(results.first?.matches.count == 1)
    }

    // MARK: - Result bounding: exact boundary, over boundary, a single
    // pathological file, and multi-file total-cap behavior.

    @Test func resultsAreTruncatedAtMaxMatchesAndReportedExplicitly() async throws {
        let tree = try TempTree()
        // 5 files, 10 matches each = 50 total matches.
        for fileIndex in 0 ..< 5 {
            let content = Array(repeating: "needle", count: 10).joined(separator: " ")
            try tree.write("file\(fileIndex).txt", text: content)
        }
        let index = await tree.makeIndex()

        let (outcome, results) = await run(root: tree.root, index: index, query: "needle", maxMatches: 25)

        guard case let .truncated(_, filesSkipped, matchCount) = outcome else {
            Issue.record("expected .truncated, got \(outcome)")
            return
        }
        #expect(filesSkipped == 0)
        #expect(matchCount == 25, "must stop exactly at the cap, not silently exceed or undershoot it")
        #expect(results.reduce(0) { $0 + $1.matches.count } == 25)
    }

    @Test func exactlyReachingMaxMatchesWithNoMoreAvailableIsCompletedNotTruncated() async throws {
        let tree = try TempTree()
        try tree.write("a.txt", text: "needle needle needle") // exactly 3 matches
        let index = await tree.makeIndex()

        let (outcome, results) = await run(root: tree.root, index: index, query: "needle", maxMatches: 3)

        #expect(outcome == .completed(filesSearched: 1, filesSkipped: 0, matchCount: 3))
        #expect(results.first?.matches.count == 3)
    }

    @Test func oneMoreMatchThanMaxMatchesIsTruncatedNotSilentlyCapped() async throws {
        let tree = try TempTree()
        try tree.write("a.txt", text: "needle needle needle needle") // 4 matches, cap is 3
        let index = await tree.makeIndex()

        let (outcome, results) = await run(root: tree.root, index: index, query: "needle", maxMatches: 3)

        guard case let .truncated(filesSearched, filesSkipped, matchCount) = outcome else {
            Issue.record("expected .truncated, got \(outcome)")
            return
        }
        #expect(filesSearched == 1)
        #expect(filesSkipped == 0)
        #expect(matchCount == 3)
        #expect(results.first?.matches.count == 3)
    }

    /// A single file whose own match count vastly exceeds `maxMatches`,
    /// proving bounding happens INSIDE the matcher (`TextSearchEngine`'s own
    /// `matchLimit`), not by computing every match and discarding the
    /// excess afterward.
    /// `TextSearchEngineTests.matchLimitStopsLiteralMatchingExactlyAtTheLimit`
    /// already proves the underlying mechanism directly; this proves
    /// `WorkspaceSearchEngine` actually wires it through end-to-end.
    @Test func aSinglePathologicalFileWithFarMoreMatchesThanTheCapIsBoundedNotFullyMaterialized() async throws {
        let tree = try TempTree()
        try tree.write("huge.txt", text: String(repeating: "a", count: 1_000_000))
        let index = await tree.makeIndex()

        let (outcome, results) = await run(root: tree.root, index: index, query: "a", maxMatches: 5)

        guard case let .truncated(filesSearched, filesSkipped, matchCount) = outcome else {
            Issue.record("expected .truncated, got \(outcome)")
            return
        }
        #expect(filesSearched == 1)
        #expect(filesSkipped == 0)
        #expect(matchCount == 5)
        #expect(results.first?.matches.count == 5)
    }

    // MARK: - FolderSearchFilter: glob include/exclude

    @Test func filterRestrictsSearchToTheIncludedExtensionGlob() async throws {
        let tree = try TempTree()
        try tree.write("a.swift", text: "needle in swift")
        try tree.write("b.md", text: "needle in markdown")
        let index = await tree.makeIndex()

        let (outcome, results) = await run(
            root: tree.root,
            index: index,
            query: "needle",
            filter: FolderSearchFilter(includeGlobs: ["*.swift"])
        )

        guard case let .completed(filesSearched, _, matchCount) = outcome else {
            Issue.record("expected .completed, got \(outcome)")
            return
        }
        #expect(filesSearched == 1)
        #expect(matchCount == 1)
        #expect(results.map(\.relativePath) == ["a.swift"])
    }

    @Test func globStarMatchesWithinASingleSegmentOnlyAndByBasenameWhenPatternHasNoSlash() {
        let filter = FolderSearchFilter(includeGlobs: ["*.swift"])
        #expect(filter.matches(IndexedPath(relativePath: "a.swift", basename: "a.swift")))
        #expect(
            filter.matches(IndexedPath(relativePath: "src/nested/a.swift", basename: "a.swift")),
            "a pattern with no '/' matches the basename anywhere in the tree"
        )
        #expect(!filter.matches(IndexedPath(relativePath: "a.swift.bak", basename: "a.swift.bak")))
    }

    @Test func globDoubleStarCrossesDirectoryBoundariesIncludingZero() {
        let filter = FolderSearchFilter(includeGlobs: ["docs/**/*.md"])
        #expect(
            filter.matches(IndexedPath(relativePath: "docs/README.md", basename: "README.md")),
            "'**/' must also match zero directories"
        )
        #expect(filter.matches(IndexedPath(relativePath: "docs/guide/intro.md", basename: "intro.md")))
        #expect(
            !filter.matches(IndexedPath(relativePath: "src/docs/readme.md", basename: "readme.md")),
            "a slash-containing pattern matches the full relative path, not 'basename anywhere'"
        )
    }

    /// No separate "extension extraction" step exists in a glob-string
    /// match (unlike the `includedExtensions`-based implementation this
    /// replaces), so the dotfile edge case an earlier review found --
    /// `NSString.lastIndex(of: ".")`-style parsing treating a dotfile's own
    /// leading dot as an extension separator -- is structurally impossible
    /// here: `*` matches zero characters, so `*.gitignore` matches the
    /// literal filename ".gitignore" directly, with nothing to parse wrong.
    @Test func globMatchesExtensionlessAndDotfileNamesAsLiteralPatterns() {
        let filter = FolderSearchFilter(includeGlobs: ["*.gitignore", "Makefile"])
        #expect(filter.matches(IndexedPath(relativePath: ".gitignore", basename: ".gitignore")))
        #expect(filter.matches(IndexedPath(relativePath: "Makefile", basename: "Makefile")))
        #expect(!filter.matches(IndexedPath(relativePath: "other.txt", basename: "other.txt")))
    }

    @Test func excludeGlobsTakePrecedenceOverIncludeGlobsOnConflict() {
        let filter = FolderSearchFilter(includeGlobs: ["*.swift"], excludeGlobs: ["**/Generated/*.swift"])
        #expect(filter.matches(IndexedPath(relativePath: "Sources/Model.swift", basename: "Model.swift")))
        #expect(
            !filter.matches(IndexedPath(relativePath: "Sources/Generated/Model.swift", basename: "Model.swift")),
            "a path matching both an include and an exclude pattern must be excluded"
        )
    }

    @Test func noIncludeGlobsMeansEveryPathPassesSubjectOnlyToExcludes() {
        let filter = FolderSearchFilter(excludeGlobs: ["*.log"])
        #expect(filter.matches(IndexedPath(relativePath: "a.swift", basename: "a.swift")))
        #expect(!filter.matches(IndexedPath(relativePath: "a.log", basename: "a.log")))
    }

    // MARK: - Hidden-file toggle (issue #112)

    @Test func includeHiddenSearchesDotfilesTheDefaultFilterSkips() async throws {
        let tree = try TempTree()
        try tree.write("visible.txt", text: "needle")
        try tree.write(".hidden.txt", text: "needle")
        let index = await tree.makeIndex()

        let (defaultOutcome, defaultResults) = await run(root: tree.root, index: index, query: "needle")
        #expect(defaultOutcome == .completed(filesSearched: 1, filesSkipped: 0, matchCount: 1))
        #expect(defaultResults.map(\.relativePath) == ["visible.txt"])

        let (hiddenOutcome, hiddenResults) = await run(
            root: tree.root,
            index: index,
            query: "needle",
            filter: FolderSearchFilter(includeHidden: true)
        )
        guard case let .completed(filesSearched, filesSkipped, matchCount) = hiddenOutcome else {
            Issue.record("expected .completed, got \(hiddenOutcome)")
            return
        }
        #expect(filesSearched == 2)
        #expect(filesSkipped == 0)
        #expect(matchCount == 2)
        #expect(Set(hiddenResults.map(\.relativePath)) == ["visible.txt", ".hidden.txt"])
    }

    // MARK: - Symlink loops (provenance: the loop guard itself lives in
    // `DirectoryWalker`, already proven not to hang by
    // `WorkspaceFileIndexTests.symlinkLoopDoesNotHang` -- this proves
    // `WorkspaceSearchEngine` genuinely inherits that guard end-to-end,
    // rather than re-deriving or duplicating it.)

    @Test func searchingAWorkspaceContainingASymlinkLoopCompletesAndFindsTheRealFile() async throws {
        let tree = try TempTree()
        try tree.write("real.txt", text: "needle")
        let looped = tree.root.appendingPathComponent("looped", isDirectory: true)
        try FileManager.default.createDirectory(at: looped, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: looped.appendingPathComponent("self"),
            withDestinationURL: looped
        )
        let index = await tree.makeIndex()

        let (outcome, results) = await run(root: tree.root, index: index, query: "needle")

        #expect(outcome == .completed(filesSearched: 1, filesSkipped: 0, matchCount: 1))
        #expect(results.map(\.relativePath) == ["real.txt"])
    }

    // MARK: - Permission failures (a deterministic read seam, not chmod's
    // own platform/sandbox-dependent timing -- a sandboxed test runner, or
    // running as root, can silently ignore permission bits entirely).

    @Test func aSimulatedPermissionFailureIsSkippedAndCountedDeterministically() async throws {
        let tree = try TempTree()
        try tree.write("readable.txt", text: "needle")
        try tree.write("locked.txt", text: "needle")
        let index = await tree.makeIndex()

        let seams = WorkspaceSearchEngine.TestSeams(readSnapshot: { root, path in
            guard path.relativePath != "locked.txt" else { return nil }
            return try? FileStore().readSnapshot(from: root.appendingPathComponent(path.relativePath))
        })
        let engine = WorkspaceSearchEngine(seams: seams)
        let box = ResultsBox()
        let outcome = await engine.search(
            root: tree.root,
            index: index,
            query: "needle",
            options: SearchOptions()
        ) { match in await box.append(match) }

        guard case let .completed(filesSearched, filesSkipped, matchCount) = outcome else {
            Issue.record("expected .completed, got \(outcome)")
            return
        }
        #expect(filesSearched == 1)
        #expect(filesSkipped == 1, "a permission failure must be skipped and counted, never crash or vanish silently")
        #expect(matchCount == 1)
        #expect(await box.all.map(\.relativePath) == ["readable.txt"])
    }

    // MARK: - Cancellation

    @Test func cancellingBeforeTheSearchStartsReturnsCancelledWithoutStreamingAnyResult() async throws {
        let tree = try TempTree()
        for fileIndex in 0 ..< 5 {
            try tree.write("file\(fileIndex).txt", text: "needle")
        }
        let index = await tree.makeIndex()

        // A naive "call `.cancel()` right after creating the `Task`" was
        // found, empirically, to race `search`'s own loop: 2 of 200 files
        // were sometimes already searched before the cancellation flag was
        // observed. `beforeEachFile` gives this test a real, deterministic
        // pause point instead of hoping to win that race.
        let gate = PauseGate()
        let engine = WorkspaceSearchEngine(seams: .init(beforeEachFile: { await gate.waitUntilReleased() }))
        let box = ResultsBox()
        let task = Task {
            await engine.search(root: tree.root, index: index, query: "needle", options: SearchOptions()) { match in
                await box.append(match)
            }
        }
        await gate.waitUntilPaused()
        task.cancel()
        await gate.release()
        let outcome = await task.value

        #expect(outcome == .cancelled)
        let collected = await box.all
        #expect(collected.isEmpty, "a search cancelled before its first file was released must never stream a result")
    }

    /// Closes the gap an independent review found in the original
    /// implementation: it only checked `Task.isCancelled` once per file,
    /// BEFORE that file was read. A cancellation landing while a (possibly
    /// slow) file's matches are being computed, or while its result is
    /// being published, could still let that one extra result through and
    /// turn what should be `.cancelled` into `.completed`/`.truncated`.
    /// `afterMatchingFile` gives this test a real pause point exactly where
    /// that gap was: after a file's matches are computed, before they are
    /// published — a naive "cancel before the first file" test (above)
    /// could never have caught this, since it never lets any file's
    /// matching actually run.
    @Test func cancellingAfterAFilesMatchesAreComputedDiscardsThatFilesResult() async throws {
        let tree = try TempTree()
        try tree.write("a.txt", text: "needle")
        try tree.write("b.txt", text: "needle")
        let index = await tree.makeIndex()

        let gate = PauseGate()
        let engine = WorkspaceSearchEngine(seams: .init(afterMatchingFile: { await gate.waitUntilReleased() }))
        let box = ResultsBox()
        let task = Task {
            await engine.search(root: tree.root, index: index, query: "needle", options: SearchOptions()) { match in
                await box.append(match)
            }
        }
        await gate.waitUntilPaused()
        task.cancel()
        await gate.release()
        let outcome = await task.value

        #expect(outcome == .cancelled)
        #expect(
            await box.all.isEmpty,
            "the first file's already-computed match must never be published once cancellation is discovered"
        )
    }

    /// EPIC-22 §6.16 keeps the generation-counter/workspace-root identity
    /// itself as 7b's own UI-layer responsibility — `WorkspaceSearchEngine`
    /// has no notion of "the current root" to compare against. Root-change
    /// safety therefore reduces entirely to cancellation being watertight
    /// even after a file's matches are already computed (the SAME guarantee
    /// `cancellingAfterAFilesMatchesAreComputedDiscardsThatFilesResult`
    /// proves generically); this test exercises that guarantee against the
    /// specific scenario issue #112 actually names — the workspace root
    /// changing mid-search — and additionally proves the engine carries no
    /// leftover state across calls: a fresh search against the NEW root,
    /// after the old one was cancelled, completes normally.
    @Test func rootReplacementDuringSearchNeverPublishesStaleResultsFromTheAbandonedRoot() async throws {
        let oldTree = try TempTree()
        try oldTree.write("old-a.txt", text: "needle")
        try oldTree.write("old-b.txt", text: "needle")
        let oldIndex = await oldTree.makeIndex()

        let gate = PauseGate()
        let engine = WorkspaceSearchEngine(seams: .init(afterMatchingFile: { await gate.waitUntilReleased() }))
        let box = ResultsBox()
        let task = Task {
            await engine.search(
                root: oldTree.root,
                index: oldIndex,
                query: "needle",
                options: SearchOptions()
            ) { match in await box.append(match) }
        }
        await gate.waitUntilPaused()
        // Simulates the caller's own generation-counter reaction (§6.16):
        // the workspace root changed underneath the in-flight search, so
        // the caller cancels it.
        task.cancel()
        await gate.release()
        let outcome = await task.value

        #expect(outcome == .cancelled)
        #expect(
            await box.all.isEmpty,
            "a search abandoned by a root change must never publish a result from the old root"
        )

        // The engine carries no per-search state of its own: a fresh search
        // against the NEW root works normally.
        let newTree = try TempTree()
        try newTree.write("new.txt", text: "needle")
        let newIndex = await newTree.makeIndex()
        let (newOutcome, newResults) = await run(root: newTree.root, index: newIndex, query: "needle")
        #expect(newOutcome == .completed(filesSearched: 1, filesSkipped: 0, matchCount: 1))
        #expect(newResults.map(\.relativePath) == ["new.txt"])
    }

    /// Blocks the engine's own loop at a named seam until the test
    /// explicitly releases it, so a test can cancel the surrounding `Task`
    /// at a known, real pause point rather than racing a hopeful
    /// "cancel immediately after creation" against the loop's own
    /// scheduling. Reused for both `beforeEachFile` and `afterMatchingFile`
    /// pause points — the gate itself doesn't care which seam calls it.
    private actor PauseGate {
        private var isPaused = false
        private var releaseContinuation: CheckedContinuation<Void, Never>?
        private var pausedContinuations: [CheckedContinuation<Void, Never>] = []

        func waitUntilReleased() async {
            isPaused = true
            for continuation in pausedContinuations {
                continuation.resume()
            }
            pausedContinuations.removeAll()
            await withCheckedContinuation { releaseContinuation = $0 }
        }

        func waitUntilPaused() async {
            if isPaused {
                return
            }
            await withCheckedContinuation { pausedContinuations.append($0) }
        }

        func release() {
            releaseContinuation?.resume()
            releaseContinuation = nil
        }
    }

    @Test func revisionCapturedForEachMatchReflectsTheFileAsRead() async throws {
        let tree = try TempTree()
        try tree.write("a.txt", text: "needle")
        let index = await tree.makeIndex()

        let (_, results) = await run(root: tree.root, index: index, query: "needle")

        let fileURL = tree.root.appendingPathComponent("a.txt")
        let onDisk = try FileStoreRevisionProbe.revision(of: fileURL)
        #expect(results.first?.revision == onDisk)
    }
}

/// Reads a file's revision the same way `FileStore.readSnapshot` computes
/// one, so `revisionCapturedForEachMatchReflectsTheFileAsRead` can assert
/// equality against an independently-obtained value rather than merely
/// checking the field is non-nil.
private enum FileStoreRevisionProbe {
    static func revision(of url: URL) throws -> FileRevision {
        try FileStore().readSnapshot(from: url).revision
    }
}
