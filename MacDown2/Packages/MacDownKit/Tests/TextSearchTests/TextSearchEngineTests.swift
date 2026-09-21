import Foundation
import Testing
@testable import TextSearch

@Suite("TextSearchEngine")
struct TextSearchEngineTests {
    // MARK: - Literal

    @Test func literalCaseSensitive() throws {
        let matches = try TextSearchEngine.matches(
            in: "Cat cat CAT",
            query: "cat",
            options: SearchOptions(isCaseSensitive: true)
        )
        #expect(matches.map(\.range) == [NSRange(location: 4, length: 3)])
    }

    @Test func literalCaseInsensitive() throws {
        let matches = try TextSearchEngine.matches(
            in: "Cat cat CAT",
            query: "cat",
            options: SearchOptions(isCaseSensitive: false)
        )
        #expect(matches.count == 3)
    }

    @Test func literalWholeWord() throws {
        let matches = try TextSearchEngine.matches(
            in: "cat category cat's cat",
            query: "cat",
            options: SearchOptions(isWholeWord: true)
        )
        // "cat" (word), "category" (not whole word), "cat's" (whole word --
        // apostrophe is not a word character), "cat" (word) = 3 matches.
        #expect(matches.count == 3)
    }

    @Test func literalEmptyQueryReturnsNoMatches() throws {
        let matches = try TextSearchEngine.matches(in: "anything", query: "", options: SearchOptions())
        #expect(matches.isEmpty)
    }

    @Test func literalNoOccurrence() throws {
        let matches = try TextSearchEngine.matches(in: "hello world", query: "xyz", options: SearchOptions())
        #expect(matches.isEmpty)
    }

    @Test func literalOverlappingOccurrencesAdvancePastEachMatch() throws {
        // "aaa" searched for "aa": matches at 0 and... after advancing past
        // the first match's END (not just +1), the next search starts at
        // index 2, finding nothing more -- this is standard non-overlapping
        // find-all behavior (matches how NSTextFinder/most editors count
        // occurrences), not overlapping matches.
        let matches = try TextSearchEngine.matches(in: "aaaa", query: "aa", options: SearchOptions())
        #expect(matches.map(\.range) == [NSRange(location: 0, length: 2), NSRange(location: 2, length: 2)])
    }

    @Test func literalUnicodeCaseFolding() throws {
        // German ß / SS-style folding and combining-vs-precomposed are two
        // different concerns; this checks basic Unicode-aware case folding
        // (İ/i, accented characters) works via `.caseInsensitive`.
        let matches = try TextSearchEngine.matches(
            in: "café CAFÉ",
            query: "café",
            options: SearchOptions(isCaseSensitive: false)
        )
        #expect(matches.count == 2)
    }

    @Test func literalCRLFDocument() throws {
        let matches = try TextSearchEngine.matches(
            in: "line1\r\nline2\r\nline1",
            query: "line1",
            options: SearchOptions()
        )
        #expect(matches.count == 2)
    }

    @Test func literalVeryLongSingleLine() throws {
        let longLine = String(repeating: "x", count: 100_000) + "NEEDLE" + String(repeating: "y", count: 100_000)
        let matches = try TextSearchEngine.matches(
            in: longLine,
            query: "NEEDLE",
            options: SearchOptions(isCaseSensitive: true)
        )
        #expect(matches.map(\.range) == [NSRange(location: 100_000, length: 6)])
    }

    // MARK: - Regex

    @Test func regexBasicMatch() throws {
        let matches = try TextSearchEngine.matches(
            in: "cat 123 dog 456",
            query: "[0-9]+",
            options: SearchOptions(isRegex: true)
        )
        #expect(matches.map(\.range) == [NSRange(location: 4, length: 3), NSRange(location: 12, length: 3)])
    }

    @Test func regexInvalidPatternThrows() {
        #expect(throws: SearchQueryError.self) {
            try TextSearchEngine.matches(in: "text", query: "[unterminated", options: SearchOptions(isRegex: true))
        }
    }

    @Test func regexZeroWidthMatchDoesNotHang() throws {
        // A zero-width-capable pattern must not cause an infinite loop --
        // NSRegularExpression's own enumerateMatches already advances past
        // zero-width matches; this just confirms the call returns.
        let matches = try TextSearchEngine.matches(in: "abc", query: "x*", options: SearchOptions(isRegex: true))
        #expect(matches.count == 4) // one zero-width match before/between/after each non-'x' character
    }

    @Test func regexWholeWordWrapsPattern() throws {
        let matches = try TextSearchEngine.matches(
            in: "cat category",
            query: "cat",
            options: SearchOptions(isRegex: true, isWholeWord: true)
        )
        #expect(matches.count == 1)
    }

    @Test func regexCaseInsensitive() throws {
        let matches = try TextSearchEngine.matches(
            in: "Cat CAT cat",
            query: "cat",
            options: SearchOptions(isRegex: true, isCaseSensitive: false)
        )
        #expect(matches.count == 3)
    }

    // MARK: - Whole-word Unicode boundary

    @Test func wholeWordAdjacentCJKLetterIsNotABoundary() throws {
        // Documented, deliberate behavior, not a bug: CJK ideographs/kana ARE
        // "word characters" under `CharacterSet.alphanumerics` (they are
        // Unicode letters), and unsegmented CJK text has no spaces between
        // words -- so a Western whole-word boundary check correctly finds no
        // boundary between "の" and "テスト" here, the same way it would find
        // no boundary between "cat" and "s" in "cats". This is a known,
        // accepted limitation (no CJK word-segmentation), not a crash or a
        // silent mis-scan -- the important property this test pins is that
        // the call completes deterministically with zero matches, not a
        // false positive or a hang.
        let matches = try TextSearchEngine.matches(
            in: "日本語のテスト",
            query: "テスト",
            options: SearchOptions(isWholeWord: true)
        )
        #expect(matches.isEmpty)
    }

    @Test func wholeWordCJKAtStringBoundaryMatches() throws {
        // With a real boundary (string start/end, not another CJK letter) on
        // both sides, CJK whole-word search does match.
        let matches = try TextSearchEngine.matches(in: "テスト", query: "テスト", options: SearchOptions(isWholeWord: true))
        #expect(matches.count == 1)
    }
}
