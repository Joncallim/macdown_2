@testable import EditorCore
import Foundation
import Testing

/// In a document that mixes `\r` and `\n`, removing or reordering text can put a lone `\r` directly in front of
/// an unrelated `\n`; the next parse reads that as ONE CRLF, so a line vanishes and terminators are rewritten
/// (invariant 5). Move, Sort, Dedupe, Duplicate, Delete and Join already declined such edits; these did not.
struct MixedTerminatorFusionTests {
    private func transaction(
        _ text: String,
        selecting range: NSRange,
        _ build: (NSString, EditorLineIndex, EditorSelectionSet) -> EditorEditTransaction?
    ) -> EditorEditTransaction? {
        let nsText = text as NSString
        return build(nsText, EditorLineIndex(text: nsText), EditorSelectionSet(single: range))
    }

    @Test func trimTrailingWhitespaceDeclinesWhenItWouldFuseCRAndLF() {
        let text = "a\r \na"

        let result = transaction(text, selecting: NSRange(location: 0, length: 0)) {
            EditorTextTransforms.trimTrailingWhitespaceTransaction(text: $0, lineIndex: $1, selection: $2)
        }

        #expect(result == nil)
    }

    @Test func trimStillWorksWhenNoPairWouldForm() {
        let text = "a \r\nb\t\nc"

        let result = transaction(text, selecting: NSRange(location: 0, length: 0)) {
            EditorTextTransforms.trimTrailingWhitespaceTransaction(text: $0, lineIndex: $1, selection: $2)
        }

        #expect(LineTransformTestSupport.applied(result, to: text)?.text == "a\r\nb\nc")
    }

    @Test func decreaseIndentDeclinesWhenItWouldFuseCRAndLF() {
        let text = "a\r \n  x\nb"

        let result = transaction(text, selecting: NSRange(location: 2, length: 0)) {
            EditorTextTransforms.indentTransaction(text: $0, lineIndex: $1, selection: $2, width: 4, decrease: true)
        }

        #expect(result == nil)
    }

    @Test func moveLineUpDeclinesWhenTheSwapWouldFuseCRAndLFInsideTheReplacement() {
        let text = "x\nb\r\ry"

        let result = transaction(
            text,
            selecting: NSRange(location: 2, length: 3),
            EditorLineTransforms.moveLinesUpTransaction
        )

        #expect(result == nil)
    }
}
