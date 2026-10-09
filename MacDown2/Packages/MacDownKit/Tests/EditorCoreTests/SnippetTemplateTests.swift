@testable import EditorCore
import Foundation
import Testing

@Suite("SnippetTemplate grammar (EPIC-22 Slice 9e)")
struct SnippetTemplateTests {
    private func expand(
        _ body: String,
        selection: String = "",
        clipboard: String? = nil,
        indent: String = "",
        lineEnding: String = "\n"
    ) -> SnippetTemplate.Expansion {
        SnippetTemplate(parsing: body).expand(
            selection: selection,
            clipboard: clipboard,
            indent: indent,
            lineEnding: lineEnding
        )
    }

    @Test func plainTextExpandsVerbatimWithTheCaretAtTheEnd() {
        let result = expand("hello")
        #expect(result.text == "hello")
        #expect(result.caretOffset == 5)
    }

    @Test func finalCaretMarkerIsRemovedAndReportsItsOffset() {
        let result = expand("a$0b")
        #expect(result.text == "ab")
        #expect(result.caretOffset == 1)
    }

    @Test func onlyTheFirstFinalCaretCountsAndLaterOnesExpandToNothing() {
        let result = expand("$0a$0b")
        #expect(result.text == "ab")
        #expect(result.caretOffset == 0)
    }

    @Test func selectionAndClipboardTokensSubstitute() {
        let result = expand("[${selection}](${clipboard})$0", selection: "text", clipboard: "https://x.test")
        #expect(result.text == "[text](https://x.test)")
        #expect(result.caretOffset == result.text.utf16.count)
    }

    @Test func aMissingClipboardExpandsToNothingAndLeaksNoToken() {
        let result = expand("<${clipboard}>", clipboard: nil)
        #expect(result.text == "<>")
        #expect(!result.text.contains("clipboard"))
    }

    @Test func anEmptyClipboardExpandsToNothing() {
        #expect(expand("<${clipboard}>", clipboard: "").text == "<>")
    }

    @Test func substitutedTextIsNeverReExpanded() {
        let result = expand("${clipboard}|${selection}", selection: "$0", clipboard: "${selection}$0")
        #expect(result.text == "${selection}$0|$0")
    }

    @Test func aBareCaretHasAnEmptySelectionToken() {
        #expect(expand("<${selection}>").text == "<>")
    }

    @Test func escapesProduceLiteralDollarAndBackslash() {
        #expect(expand("\\$0 \\\\ \\${selection}").text == "$0 \\ ${selection}")
        #expect(expand("\\$0").caretOffset == 2)
    }

    @Test func aLoneBackslashOrUnknownTokenStaysLiteral() {
        #expect(expand("a\\b").text == "a\\b")
        #expect(expand("$1 ${name} $ $").text == "$1 ${name} $ $")
    }

    @Test func noShellOrCommandSubstitutionIsEverInterpreted() {
        let body = "$(rm -rf /) `date` ${env:HOME} $HOME"
        #expect(expand(body).text == body)
    }

    @Test func bodyLineBreaksBecomeTheDocumentsTerminatorPlusIndent() {
        let result = expand("a\nb\r\nc\rd", indent: "  ", lineEnding: "\r\n")
        #expect(result.text == "a\r\n  b\r\n  c\r\n  d")
    }

    @Test func finalCaretOffsetIsCountedInUTF16Units() {
        let result = expand("\u{1F600}$0x")
        #expect(result.text == "\u{1F600}x")
        #expect(result.caretOffset == 2)
    }

    @Test func emptyBodyExpandsToNothing() {
        let result = expand("")
        #expect(result.text.isEmpty)
        #expect(result.caretOffset == 0)
    }

    @Test func aTrailingLoneBackslashStaysLiteral() {
        #expect(expand("a\\").text == "a\\")
    }

    @Test func finalCaretFollowedByDigitsIsStillTheFinalCaret() {
        let result = expand("a$01")
        #expect(result.text == "a1")
        #expect(result.caretOffset == 1)
    }

    @Test func anEscapedSelectionTokenIsLiteralNotSubstituted() {
        #expect(expand("\\${selection}", selection: "X").text == "${selection}")
    }

    @Test func crlfAndLoneCRInABodyEachBecomeOneTerminator() {
        #expect(expand("a\r\nb\rc", lineEnding: "\r\n").text == "a\r\nb\r\nc")
    }

    @Test func selectionInsideAMultiLineBodyKeepsTheIndentOnLaterBodyLinesOnly() {
        let result = expand("a\n${selection}", selection: "x\ny", indent: "  ")
        #expect(result.text == "a\n  x\ny")
    }
}
