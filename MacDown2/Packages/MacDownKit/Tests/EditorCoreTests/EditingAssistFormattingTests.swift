@testable import EditorCore
import Foundation
import Testing

@Suite("Editing assists — Markdown formatting commands")
struct EditingAssistFormattingTests {
    private let support = EditingAssistTestSupport.self

    private func command(_ command: MarkdownEditingCommand, in text: String,
                         selection: NSRange) -> EditingAssistOutcome
    // swiftlint:disable:next opening_brace
    {
        support.outcome(for: .markdownCommand(command), in: text, selection: selection)
    }

    @Test("Bold wraps and toggles off")
    func boldWrapsAndToggles() {
        let wrap = command(.bold, in: "foo", selection: NSRange(location: 0, length: 3))
        let wrapResult = support.applied(wrap, to: "foo")
        #expect(wrapResult?.text == "**foo**")
        #expect(wrapResult?.selection == NSRange(location: 2, length: 3))

        let toggle = command(.bold, in: "**foo**", selection: NSRange(location: 2, length: 3))
        let toggleResult = support.applied(toggle, to: "**foo**")
        #expect(toggleResult?.text == "foo")
        #expect(toggleResult?.selection == NSRange(location: 0, length: 3))
    }

    @Test("Italic wraps and toggles off")
    func italicWrapsAndToggles() {
        let wrap = command(.italic, in: "foo", selection: NSRange(location: 0, length: 3))
        let wrapResult = support.applied(wrap, to: "foo")
        #expect(wrapResult?.text == "*foo*")
        #expect(wrapResult?.selection == NSRange(location: 1, length: 3))

        let toggle = command(.italic, in: "*foo*", selection: NSRange(location: 1, length: 3))
        let toggleResult = support.applied(toggle, to: "*foo*")
        #expect(toggleResult?.text == "foo")
        #expect(toggleResult?.selection == NSRange(location: 0, length: 3))
    }

    @Test("Italic does not strip a only-strong ** selection")
    func italicDoesNotStripStrong() {
        let outcome = command(.italic, in: "**foo**", selection: NSRange(location: 2, length: 3))
        let result = support.applied(outcome, to: "**foo**")
        #expect(result?.text == "***foo***")
        #expect(result?.selection == NSRange(location: 3, length: 3))
    }

    @Test("Italic recognizes outer single stars in ***selection***")
    func italicRecognizesTripleSurrounded() {
        // The single-star layer is stripped, leaving the strong layer.
        let outcome = command(.italic, in: "***foo***", selection: NSRange(location: 3, length: 3))
        let result = support.applied(outcome, to: "***foo***")
        #expect(result?.text == "**foo**")
        #expect(result?.selection == NSRange(location: 2, length: 3))
    }

    @Test("Inline Code wraps and toggles off")
    func inlineCodeWrapsAndToggles() {
        let wrap = command(.inlineCode, in: "foo", selection: NSRange(location: 0, length: 3))
        let wrapResult = support.applied(wrap, to: "foo")
        #expect(wrapResult?.text == "`foo`")
        #expect(wrapResult?.selection == NSRange(location: 1, length: 3))

        let toggle = command(.inlineCode, in: "`foo`", selection: NSRange(location: 1, length: 3))
        let toggleResult = support.applied(toggle, to: "`foo`")
        #expect(toggleResult?.text == "foo")
        #expect(toggleResult?.selection == NSRange(location: 0, length: 3))
    }

    @Test("empty selection inserts delimiters with the caret inside")
    func emptySelectionInsertsDelimiters() {
        let bold = command(.bold, in: "", selection: NSRange(location: 0, length: 0))
        let boldResult = support.applied(bold, to: "")
        #expect(boldResult?.text == "****")
        #expect(boldResult?.selection == NSRange(location: 2, length: 0))

        let italic = command(.italic, in: "", selection: NSRange(location: 0, length: 0))
        let italicResult = support.applied(italic, to: "")
        #expect(italicResult?.text == "**")
        #expect(italicResult?.selection == NSRange(location: 1, length: 0))

        let code = command(.inlineCode, in: "", selection: NSRange(location: 0, length: 0))
        let codeResult = support.applied(code, to: "")
        #expect(codeResult?.text == "``")
        #expect(codeResult?.selection == NSRange(location: 1, length: 0))
    }

    @Test("headings replace the existing ATX level rather than stacking")
    func headingsReplaceLevel() {
        let plain = command(.heading(level: 2), in: "foo", selection: NSRange(location: 0, length: 3))
        let plainResult = support.applied(plain, to: "foo")
        #expect(plainResult?.text == "## foo")

        let existing = command(.heading(level: 3), in: "## foo", selection: NSRange(location: 0, length: 6))
        let existingResult = support.applied(existing, to: "## foo")
        #expect(existingResult?.text == "### foo")

        // "#foo" without a following space is content, not a heading prefix.
        let noSpace = command(.heading(level: 1), in: "#foo", selection: NSRange(location: 0, length: 4))
        let noSpaceResult = support.applied(noSpace, to: "#foo")
        #expect(noSpaceResult?.text == "# #foo")
    }

    @Test("Paragraph strips the ATX prefix")
    func paragraphStripsPrefix() {
        let outcome = command(.paragraph, in: "### foo", selection: NSRange(location: 0, length: 7))
        let result = support.applied(outcome, to: "### foo")
        #expect(result?.text == "foo")
    }

    @Test("multi-line heading skips blank interior lines")
    func multiLineHeadingSkipsBlankLines() {
        let outcome = command(.heading(level: 1), in: "a\n\nb", selection: NSRange(location: 0, length: 4))
        let result = support.applied(outcome, to: "a\n\nb")
        #expect(result?.text == "# a\n\n# b")
        #expect(result?.selection == NSRange(location: 0, length: 8))
    }

    @Test("selection tracks the same logical content after positive and negative per-line shifts")
    func selectionTracksPerLineShifts() {
        // Mixed selection: first line gains two units, second loses three.
        let text = "## a\n### b"
        let outcome = command(.heading(level: 1), in: text, selection: NSRange(location: 3, length: 6))
        let result = support.applied(outcome, to: text)
        #expect(result?.text == "# a\n# b")
        // Selection started at "a" (after "## ") and covered "a\n### ".
        #expect(result?.selection == NSRange(location: 2, length: 4))
    }

    @Test("CRLF range stays valid")
    func crlfRangeStaysValid() {
        let outcome = command(.heading(level: 1), in: "a\r\nb", selection: NSRange(location: 0, length: 4))
        let result = support.applied(outcome, to: "a\r\nb")
        #expect(result?.text == "# a\r\n# b")
        #expect(result?.selection == NSRange(location: 0, length: 8))
    }

    @Test("heading on a blank single line inserts the prefix for immediate typing")
    func headingOnBlankLineInsertsPrefix() {
        let outcome = command(.heading(level: 2), in: "", selection: NSRange(location: 0, length: 0))
        let result = support.applied(outcome, to: "")
        #expect(result?.text == "## ")
        #expect(result?.selection == NSRange(location: 3, length: 0))

        let whitespace = command(.heading(level: 1), in: "   ", selection: NSRange(location: 0, length: 3))
        let whitespaceResult = support.applied(whitespace, to: "   ")
        #expect(whitespaceResult?.text == "# ")
        #expect(whitespaceResult?.selection == NSRange(location: 2, length: 0))
    }

    @Test("Paragraph on a blank single line is a deliberate no-op")
    func paragraphOnBlankLineIsNoOp() {
        let outcome = command(.paragraph, in: "   ", selection: NSRange(location: 0, length: 3))
        #expect(outcome == .handledNoChange)
    }

    @Test("invalid heading levels never reach the engine as edits")
    func invalidHeadingLevelRejected() {
        // The engine itself refuses out-of-range levels.
        let outcome = command(.heading(level: 7), in: "foo", selection: NSRange(location: 0, length: 3))
        #expect(outcome == .passthrough)
        let zero = command(.heading(level: 0), in: "foo", selection: NSRange(location: 0, length: 3))
        #expect(zero == .passthrough)
    }
}
