@testable import EditorCore
import Foundation
import Testing

/// Handoff regression 6 (#381): the Markdown-assist Tab / Shift-Tab path (and the heading command, which shares the
/// line helpers) treated a lone CR as ordinary line content, so a bare-CR or mixed-EOL selection indented only the
/// first logical line and a caret in a later CR-terminated line expanded to the whole document.
@Suite("Editing assists — bare CR and mixed line endings")
struct EditingAssistBareCRTests {
    private let support = EditingAssistTestSupport.self

    private func tab(_ text: String, _ selection: NSRange) -> (text: String, selection: NSRange)? {
        support.applied(support.outcome(for: .insertTab, in: text, selection: selection), to: text)
    }

    private func backtab(_ text: String, _ selection: NSRange) -> (text: String, selection: NSRange)? {
        support.applied(support.outcome(for: .insertBacktab, in: text, selection: selection), to: text)
    }

    @Test func tabOnASelectionSpanningBareCRLinesIndentsEveryLogicalLine() {
        let text = "a\rb\rc"
        let result = tab(text, NSRange(location: 0, length: text.utf16.count))
        #expect(result?.text == "    a\r    b\r    c")
    }

    @Test func tabOnAMixedEOLSelectionIndentsEveryLineAndKeepsEachTerminator() {
        let text = "a\rb\nc\r\nd"
        let result = tab(text, NSRange(location: 0, length: text.utf16.count))
        #expect(result?.text == "    a\r    b\n    c\r\n    d")
    }

    @Test func aSelectionOfTwoBareCRLinesLeavesTheLaterOnesAlone() {
        let text = "a\rb\rc\rd"
        // Select from inside line b to inside line c.
        let result = tab(text, NSRange(location: 3, length: 3))
        #expect(result?.text == "a\r    b\r    c\rd")
    }

    @Test func aCaretSelectionOnABareCRLineOnlyAffectsThatLine() {
        let text = "a\rb\rc"
        let result = tab(text, NSRange(location: 2, length: 1)) // selects "b"
        #expect(result?.text == "a\r    b\rc")
    }

    @Test func aTrailingBareCRIsNotIndentedAsASyntheticLine() {
        let text = "a\rb\r"
        let result = tab(text, NSRange(location: 0, length: text.utf16.count))
        #expect(result?.text == "    a\r    b\r")
    }

    @Test func backtabUnindentsEveryBareCRLine() {
        let text = "    a\r  b\r\tc"
        let result = backtab(text, NSRange(location: 0, length: text.utf16.count))
        #expect(result?.text == "a\rb\rc")
    }

    @Test func theHeadingCommandAppliesToEachBareCRLineAndKeepsTheSeparators() {
        let text = "a\rb\nc"
        let outcome = support.outcome(
            for: .markdownCommand(.heading(level: 2)),
            in: text,
            selection: NSRange(location: 0, length: 5)
        )
        let result = support.applied(outcome, to: text)
        #expect(result?.text == "## a\r## b\n## c")
    }
}
