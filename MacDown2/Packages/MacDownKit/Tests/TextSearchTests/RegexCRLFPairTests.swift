import Foundation
import Testing
@testable import TextSearch

/// Review pass 7: ICU `\n` matches only the LF of a CRLF pair and `.*` can match empty between the CR and LF, so a
/// Replace All left lone CRs or inserted text inside the pair.
struct RegexCRLFPairTests {
    private func ranges(_ pattern: String, in text: String) throws -> [NSRange] {
        try TextSearchEngine.matches(in: text, query: pattern, options: SearchOptions(isRegex: true)).map(\.range)
    }

    @Test func aNewlinePatternMatchesTheWholeCRLF() throws {
        #expect(try ranges("\\n", in: "a\r\nb\r\nc") == [
            NSRange(location: 1, length: 2),
            NSRange(location: 4, length: 2),
        ])
    }

    @Test func aBareLFIsStillJustTheLF() throws {
        #expect(try ranges("\\n", in: "a\nb") == [NSRange(location: 1, length: 1)])
    }

    @Test func anEmptyMatchBetweenCRAndLFIsDropped() throws {
        let found = try ranges("[a-z]*", in: "ab\r\ncd")

        #expect(!found.contains { $0.length == 0 && $0.location == 3 })
        #expect(found.contains(NSRange(location: 0, length: 2)))
    }

    @Test func aCRPatternStillMatchesOnlyTheCR() throws {
        #expect(try ranges("\\r", in: "a\r\nb") == [NSRange(location: 1, length: 1)])
    }

    /// Review pass 8 (regression from the first version): when the previous match already covered the CR, the LF match
    /// was discarded, so `[\r\n]` / `\s` Replace All with "" produced `a\nb\nc` instead of `abc`.
    @Test(arguments: ["[\\r\\n]", "\\s", "\\r|\\n", "[^a-z]"])
    func aPatternThatMatchesTheCRAndTheLFSeparatelyKeepsBothHalves(_ pattern: String) throws {
        let found = try ranges(pattern, in: "a\r\nb\r\nc")

        #expect(found == [
            NSRange(location: 1, length: 1), NSRange(location: 2, length: 1),
            NSRange(location: 4, length: 1), NSRange(location: 5, length: 1),
        ])
    }
}
