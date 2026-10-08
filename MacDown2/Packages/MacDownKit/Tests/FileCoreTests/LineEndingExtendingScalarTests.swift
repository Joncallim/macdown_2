@testable import FileCore
import Foundation
import Testing

/// Review pass 8: non-literal `replacingOccurrences` treats a CR or LF followed by a combining scalar as one unit, so
/// that break was skipped by one step and rewritten by the next — an extra blank line, or a bare LF kept in a CRLF
/// document (Replace, Replace All, Replace in Folder, snippet clipboard).
struct LineEndingExtendingScalarTests {
    @Test func aCRLFFollowedByACombiningMarkBecomesExactlyOneLF() {
        #expect(LineEnding.adaptingLineBreaks(in: "x\r\n\u{301}y", to: .lineFeed) == "x\n\u{301}y")
    }

    @Test func aCRLFFollowedByACombiningMarkBecomesExactlyOneCRLF() {
        #expect(LineEnding.adaptingLineBreaks(in: "x\r\n\u{301}y", to: .crlf) == "x\r\n\u{301}y")
    }

    @Test func aBareLFFollowedByACombiningMarkBecomesACRLF() {
        #expect(LineEnding.adaptingLineBreaks(in: "x\n\u{200C}y", to: .crlf) == "x\r\n\u{200C}y")
    }
}
