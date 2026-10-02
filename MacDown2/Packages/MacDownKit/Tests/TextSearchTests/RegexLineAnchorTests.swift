import Testing
@testable import TextSearch

/// Review pass 1: `^` and `$` must match at line boundaries.
struct RegexLineAnchorTests {
    private let regex = SearchOptions(isRegex: true)

    @Test func caretMatchesAtTheStartOfEveryLine() throws {
        let matches = try TextSearchEngine.matches(in: "# one\n# two\n# three", query: "^# ", options: regex)
        #expect(matches.count == 3)
    }

    @Test func dollarMatchesAtTheEndOfEveryLine() throws {
        let matches = try TextSearchEngine.matches(in: "one\ntwo\nthree", query: "$", options: regex)
        #expect(matches.count == 3)
    }

    @Test func caretMatchesAfterCRLFAndBareCR() throws {
        #expect(try TextSearchEngine.matches(in: "a\r\nb\r\nc", query: "^[abc]", options: regex).count == 3)
        #expect(try TextSearchEngine.matches(in: "a\rb\rc", query: "^[abc]", options: regex).count == 3)
    }
}
