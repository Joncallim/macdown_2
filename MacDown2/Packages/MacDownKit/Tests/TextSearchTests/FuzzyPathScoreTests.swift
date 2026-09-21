import Testing
@testable import TextSearch

@Suite("FuzzyPathScore")
struct FuzzyPathScoreTests {
    @Test func exactBasenameScoresHighest() throws {
        let exact = FuzzyPathScore.score(query: "main.swift", path: "Sources/App/main.swift", basename: "main.swift")
        let prefix = FuzzyPathScore.score(query: "main", path: "Sources/App/main.swift", basename: "main.swift")
        #expect(try #require(exact) > (try #require(prefix)))
    }

    @Test func basenamePrefixScoresHigherThanFuzzy() throws {
        let prefix = FuzzyPathScore.score(
            query: "wind",
            path: "Sources/App/WindowCoordinator.swift",
            basename: "WindowCoordinator.swift"
        )
        let fuzzy = FuzzyPathScore.score(
            query: "wdc",
            path: "Sources/App/WindowCoordinator.swift",
            basename: "WindowCoordinator.swift"
        )
        #expect(try #require(prefix) > (try #require(fuzzy)))
    }

    @Test func basenameFuzzyScoresHigherThanPathOnlyFuzzy() throws {
        // Query fuzzy-matches the basename directly vs. only matching
        // somewhere in the full path (e.g. a directory component).
        let basenameMatch = FuzzyPathScore.score(
            query: "edt",
            path: "Sources/EditorCore/EditorTextSystem.swift",
            basename: "EditorTextSystem.swift"
        )
        let pathOnlyMatch = FuzzyPathScore.score(
            query: "src",
            path: "Sources/EditorCore/EditorTextSystem.swift",
            basename: "EditorTextSystem.swift"
        )
        #expect(basenameMatch != nil)
        #expect(pathOnlyMatch != nil)
        #expect(try #require(basenameMatch) > (try #require(pathOnlyMatch)))
    }

    @Test func nonSubsequenceReturnsNil() {
        #expect(FuzzyPathScore.score(query: "zzz", path: "Sources/main.swift", basename: "main.swift") == nil)
    }

    @Test func outOfOrderCharactersDoNotMatch() {
        // "nim" is not a subsequence of "main" (n comes after m, i, before a).
        #expect(FuzzyPathScore.score(query: "nim", path: "main.swift", basename: "main.swift") == nil)
    }

    @Test func emptyQueryMatchesEverythingWithBaseScore() {
        #expect(FuzzyPathScore.score(query: "", path: "anything.swift", basename: "anything.swift") == 0)
    }

    @Test func caseInsensitiveAndDiacriticInsensitive() {
        #expect(FuzzyPathScore.score(query: "CAFE", path: "café.md", basename: "café.md") != nil)
        // "MAIN" vs "Main.swift": the basename includes its extension, so
        // this is correctly a prefix match (900), not an exact one (1000) --
        // exact match requires the query to equal the whole basename.
        #expect(FuzzyPathScore.score(query: "MAIN", path: "Main.swift", basename: "Main.swift") == 900)
        #expect(FuzzyPathScore.score(query: "MAIN.SWIFT", path: "Main.swift", basename: "Main.swift") == 1000)
    }

    @Test func contiguousMatchScoresHigherThanScattered() throws {
        let contiguous = FuzzyPathScore.score(query: "wind", path: "Windows.swift", basename: "Windows.swift")
        let scattered = FuzzyPathScore.score(query: "wnds", path: "Windows.swift", basename: "Windows.swift")
        #expect(try #require(contiguous) > (try #require(scattered)))
    }

    @Test func earlierMatchScoresHigherThanLater() throws {
        let early = FuzzyPathScore.score(
            query: "ab",
            path: "ab_long_suffix_zzzzzzzzzzzzzzzzzzzz.swift",
            basename: "ab_long_suffix_zzzzzzzzzzzzzzzzzzzz.swift"
        )
        let late = FuzzyPathScore.score(
            query: "zz",
            path: "ab_long_suffix_zzzzzzzzzzzzzzzzzzzz.swift",
            basename: "ab_long_suffix_zzzzzzzzzzzzzzzzzzzz.swift"
        )
        #expect(try #require(early) > (try #require(late)))
    }
}
