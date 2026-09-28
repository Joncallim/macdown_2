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

    @Test func filterRestrictsSearchToTheIncludedExtension() async throws {
        let tree = try TempTree()
        try tree.write("a.swift", text: "needle in swift")
        try tree.write("b.md", text: "needle in markdown")
        let index = await tree.makeIndex()

        let (outcome, results) = await run(
            root: tree.root,
            index: index,
            query: "needle",
            filter: FolderSearchFilter(includedExtensions: ["swift"])
        )

        guard case let .completed(filesSearched, _, matchCount) = outcome else {
            Issue.record("expected .completed, got \(outcome)")
            return
        }
        #expect(filesSearched == 1)
        #expect(matchCount == 1)
        #expect(results.map(\.relativePath) == ["a.swift"])
    }

    /// `FolderSearchFilter.matches(_:)` directly, not through the full
    /// engine: a dotfile (e.g. `.gitignore`) never actually reaches this
    /// filter in production (`DirectoryWalker` excludes every hidden entry
    /// before it reaches the index), but an independent review of this
    /// slice found a hand-rolled `lastIndex(of: ".")` split would have
    /// treated its own leading dot as an extension separator
    /// (`.gitignore` -> "gitignore") had it ever been reached — fixed to
    /// use `NSString.pathExtension`'s own platform-standard semantics
    /// instead. Tests the filter directly, against a synthetic
    /// `IndexedPath`, so this stays correct even if a later slice reuses
    /// `FolderSearchFilter` against a path source that does not already
    /// exclude dotfiles.
    @Test func extensionMatchingUsesPlatformSemanticsForDotfilesAndExtensionlessNames() {
        let filter = FolderSearchFilter(includedExtensions: ["gitignore"])
        let dotfile = IndexedPath(relativePath: ".gitignore", basename: ".gitignore")
        #expect(!filter.matches(dotfile), "a dotfile's own leading dot must never be read as its extension")

        let extensionless = IndexedPath(relativePath: "Makefile", basename: "Makefile")
        #expect(!filter.matches(extensionless))

        let trailingDot = IndexedPath(relativePath: "file.", basename: "file.")
        #expect(!filter.matches(trailingDot))

        let real = IndexedPath(relativePath: "a.gitignore", basename: "a.gitignore")
        #expect(filter.matches(real))
    }

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
        let engine = WorkspaceSearchEngine(beforeEachFile: { await gate.waitUntilReleased() })
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

    /// Blocks the engine's own loop at `beforeEachFile` until the test
    /// explicitly releases it, so a test can cancel the surrounding `Task`
    /// at a known, real pause point rather than racing a hopeful
    /// "cancel immediately after creation" against the loop's own scheduling.
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
