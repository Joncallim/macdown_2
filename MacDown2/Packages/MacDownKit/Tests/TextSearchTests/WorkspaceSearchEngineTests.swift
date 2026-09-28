import FileCore
import Foundation
import Testing
@testable import TextSearch

/// A real temporary directory tree, torn down after the test. Shared by
/// `WorkspaceSearchEngineTests` and `WorkspaceSearchEngineCancellationTests`
/// (hoisted to module scope rather than duplicated per suite, and kept out
/// of either `@Suite` struct's own body so neither trips SwiftLint's
/// `type_body_length` limit).
final class WorkspaceSearchEngineTempTree {
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
actor WorkspaceSearchEngineResultsBox {
    private(set) var all: [FolderSearchMatch] = []
    func append(_ match: FolderSearchMatch) {
        all.append(match)
    }
}

/// Runs a search and returns both the outcome and every streamed
/// result, collected in order — the shared shape almost every test
/// across both `WorkspaceSearchEngine` test suites needs, so each test
/// states only what differs.
func runFolderSearch(
    root: URL,
    index: WorkspaceFileIndex,
    query: String,
    options: SearchOptions = SearchOptions(),
    filter: FolderSearchFilter = FolderSearchFilter(),
    maxMatches: Int = WorkspaceSearchEngine.defaultMaxMatches
) async -> (outcome: FolderSearchOutcome, results: [FolderSearchMatch]) {
    let box = WorkspaceSearchEngineResultsBox()
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

@Suite("WorkspaceSearchEngine")
struct WorkspaceSearchEngineTests {
    @Test func streamsOneMatchGroupPerFileInIndexedOrder() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.txt", text: "hello world\nhello again")
        try tree.write("b.txt", text: "nothing here")
        try tree.write("c.txt", text: "another hello")
        let index = await tree.makeIndex()

        let (outcome, results) = await runFolderSearch(root: tree.root, index: index, query: "hello")

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
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.txt", text: "hello world")
        let index = await tree.makeIndex()

        let (outcome, results) = await runFolderSearch(root: tree.root, index: index, query: "")

        #expect(outcome == .completed(filesSearched: 0, filesSkipped: 0, matchCount: 0))
        #expect(results.isEmpty)
    }

    @Test func invalidRegexIsReportedOnceWithoutTouchingAnyFile() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.txt", text: "hello world")
        let index = await tree.makeIndex()

        let (outcome, results) = await runFolderSearch(
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
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("readable.txt", text: "hello world")
        try tree.writeBinary("binary.dat")
        let index = await tree.makeIndex()

        let (outcome, results) = await runFolderSearch(root: tree.root, index: index, query: "hello")

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
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.txt", text: "CAFÉ and café and Café")
        let index = await tree.makeIndex()

        let (_, results) = await runFolderSearch(
            root: tree.root,
            index: index,
            query: "café",
            options: SearchOptions(isCaseSensitive: false)
        )

        #expect(results.first?.matches.count == 3)
    }

    @Test func crlfContentIsSearchedCorrectly() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.txt", text: "line one\r\nhello\r\nline three\r\n")
        let index = await tree.makeIndex()

        let (_, results) = await runFolderSearch(root: tree.root, index: index, query: "hello")

        #expect(results.first?.matches.count == 1)
    }

    @Test func aHugeSingleLineIsSearchedWithoutHanging() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        let huge = String(repeating: "x", count: 2_000_000) + "needle" + String(repeating: "y", count: 2_000_000)
        try tree.write("huge.txt", text: huge)
        let index = await tree.makeIndex()

        let (outcome, results) = await runFolderSearch(root: tree.root, index: index, query: "needle")

        #expect(outcome == .completed(filesSearched: 1, filesSkipped: 0, matchCount: 1))
        #expect(results.first?.matches.count == 1)
    }

    // MARK: - Result bounding: exact boundary, over boundary, a single

    // pathological file, and multi-file total-cap behavior.

    @Test func resultsAreTruncatedAtMaxMatchesAndReportedExplicitly() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        // 5 files, 10 matches each = 50 total matches.
        for fileIndex in 0 ..< 5 {
            let content = Array(repeating: "needle", count: 10).joined(separator: " ")
            try tree.write("file\(fileIndex).txt", text: content)
        }
        let index = await tree.makeIndex()

        let (outcome, results) = await runFolderSearch(root: tree.root, index: index, query: "needle", maxMatches: 25)

        guard case let .truncated(_, filesSkipped, matchCount) = outcome else {
            Issue.record("expected .truncated, got \(outcome)")
            return
        }
        #expect(filesSkipped == 0)
        #expect(matchCount == 25, "must stop exactly at the cap, not silently exceed or undershoot it")
        #expect(results.reduce(0) { $0 + $1.matches.count } == 25)
    }

    @Test func exactlyReachingMaxMatchesWithNoMoreAvailableIsCompletedNotTruncated() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.txt", text: "needle needle needle") // exactly 3 matches
        let index = await tree.makeIndex()

        let (outcome, results) = await runFolderSearch(root: tree.root, index: index, query: "needle", maxMatches: 3)

        #expect(outcome == .completed(filesSearched: 1, filesSkipped: 0, matchCount: 3))
        #expect(results.first?.matches.count == 3)
    }

    @Test func oneMoreMatchThanMaxMatchesIsTruncatedNotSilentlyCapped() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.txt", text: "needle needle needle needle") // 4 matches, cap is 3
        let index = await tree.makeIndex()

        let (outcome, results) = await runFolderSearch(root: tree.root, index: index, query: "needle", maxMatches: 3)

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
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("huge.txt", text: String(repeating: "a", count: 1_000_000))
        let index = await tree.makeIndex()

        let (outcome, results) = await runFolderSearch(root: tree.root, index: index, query: "a", maxMatches: 5)

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
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.swift", text: "needle in swift")
        try tree.write("b.md", text: "needle in markdown")
        let index = await tree.makeIndex()

        let (outcome, results) = await runFolderSearch(
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
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("visible.txt", text: "needle")
        try tree.write(".hidden.txt", text: "needle")
        let index = await tree.makeIndex()

        let (defaultOutcome, defaultResults) = await runFolderSearch(root: tree.root, index: index, query: "needle")
        #expect(defaultOutcome == .completed(filesSearched: 1, filesSkipped: 0, matchCount: 1))
        #expect(defaultResults.map(\.relativePath) == ["visible.txt"])

        let (hiddenOutcome, hiddenResults) = await runFolderSearch(
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

    @Test func revisionCapturedForEachMatchReflectsTheFileAsRead() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.txt", text: "needle")
        let index = await tree.makeIndex()

        let (_, results) = await runFolderSearch(root: tree.root, index: index, query: "needle")

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
