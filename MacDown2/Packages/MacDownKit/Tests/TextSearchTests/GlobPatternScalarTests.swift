import Foundation
import Testing
@testable import TextSearch

/// Review pass 8: the matcher worked on `Character`s, so a `/` merged with a following combining mark was neither a
/// literal `/` nor a segment boundary: `drafts/*.md` crossed directories and `private/**` missed `private/\u{301}x.md`
/// (a file the user excluded was still searched and could be rewritten).
struct GlobPatternScalarTests {
    @Test func aStarStillDoesNotCrossASlashGluedToAMark() {
        #expect(!GlobPattern.matches(pattern: "drafts/*.md", text: "drafts/sub/\u{301}x.md"))
        #expect(GlobPattern.matches(pattern: "drafts/*.md", text: "drafts/x.md"))
    }

    @Test func aDoubleStarMatchesAFileWhoseNameStartsWithAMark() {
        #expect(GlobPattern.matches(pattern: "private/**", text: "private/\u{301}x.md"))
        #expect(GlobPattern.matches(pattern: "private/**", text: "private/a/\u{200C}b.md"))
    }

    @Test func ordinaryPatternsAreUnchanged() {
        #expect(GlobPattern.matches(pattern: "**/*.md", text: "README.md"))
        #expect(GlobPattern.matches(pattern: "*.SWIFT", text: "a.swift"))
        #expect(!GlobPattern.matches(pattern: "*.swift", text: "a.md"))
    }
}
