@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 §6.13, Slice 4c-ii — pure-logic tests for Sort Lines, Dedupe
/// Lines, and Trim Trailing Whitespace, entirely independent of `NSTextView`.
@Suite("EditorTextTransforms (Slice 4c-ii)")
struct EditorTextTransformsTests {
    // MARK: - Sort Lines

    @Test("sorting a selected block sorts its lines by content")
    func sortBasic() {
        let text = "banana\napple\ncherry" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorTextTransforms.sortLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "apple\nbanana\ncherry")
    }

    @Test("sorting preserves the block's own CRLF terminators, positionally")
    func sortPreservesCRLF() {
        let text = "banana\r\napple\r\ncherry" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorTextTransforms.sortLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "apple\r\nbanana\r\ncherry")
    }

    @Test("sorting never touches content after the selected block")
    func sortDoesNotTouchFollowingContent() {
        let text = "banana\napple\ncherry\nzzz" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: 13)) // "banana\napple\n" -- lines 1-2

        let transaction = EditorTextTransforms.sortLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "apple\nbanana\ncherry\nzzz")
    }

    @Test("sorting a single-line selection is a no-op")
    func sortSingleLineIsNoOp() {
        let text = "AAA" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 1, length: 0))

        let transaction = EditorTextTransforms.sortLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        #expect(transaction == nil)
    }

    @Test("two selections that expand to overlapping line-blocks merge into one sort")
    func sortMergesOverlappingExpandedBlocks() {
        // A real risk this type's own design specifically had to reason
        // about: expanding a raw selection to the whole lines it touches
        // can make two originally-DISJOINT selections claim the same line,
        // which would otherwise build two overlapping (invalid) replacement
        // ranges. Reusing `EditorLineTransforms.mergedLineBlockGroups`
        // resolves this the same way Duplicate/Delete already do.
        let text = "ccc\nbbb\naaa" as NSString
        let lineIndex = EditorLineIndex(text: text)
        // Selection A ends mid-line-2, selection B starts mid-line-2 --
        // both expand to include line 2's own full content.
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 5), NSRange(location: 6, length: 5)], // "ccc\nb" / "b\naaa"
            primaryIndex: 0
        )

        let transaction = EditorTextTransforms.sortLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        #expect(transaction?.replacements.count == 1)
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)
        #expect(applied?.text == "aaa\nbbb\nccc")
    }

    // MARK: - Dedupe Lines

    @Test("deduping removes a later exact duplicate, keeping the first occurrence")
    func dedupeBasic() {
        let text = "apple\nbanana\napple\ncherry" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorTextTransforms.dedupeLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "apple\nbanana\ncherry")
    }

    @Test("deduping is case-sensitive -- differently-cased lines are NOT duplicates")
    func dedupeIsCaseSensitive() {
        let text = "Apple\napple\nApple" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorTextTransforms.dedupeLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "Apple\napple")
    }

    @Test("deduping removes the ORIGINAL last line's own terminator correctly when that line is a duplicate")
    func dedupeRemovingTheLastLineLeavesNoTrailingSeparator() {
        // A P1-class bug this design specifically had to avoid (learned
        // from Slice 4c-i's own hostile-review finding): if the block's own
        // final line is itself a removed duplicate, the terminator that
        // used to sit before it must NOT be resurrected as a spurious
        // trailing separator on the new final line.
        let text = "apple\nbanana\napple" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorTextTransforms.dedupeLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "apple\nbanana")
    }

    @Test("deduping preserves CRLF terminators of the surviving lines")
    func dedupePreservesCRLF() {
        let text = "apple\r\nbanana\r\napple\r\ncherry" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorTextTransforms.dedupeLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "apple\r\nbanana\r\ncherry")
    }

    @Test("deduping a single-line selection is a no-op")
    func dedupeSingleLineIsNoOp() {
        let text = "AAA" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 1, length: 0))

        let transaction = EditorTextTransforms.dedupeLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        #expect(transaction == nil)
    }

    // MARK: - Trim Trailing Whitespace

    @Test("trimming removes trailing spaces and tabs from every line in the whole document")
    func trimBasic() {
        let text = "foo  \nbar\t\nbaz" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: 0))

        let transaction = EditorTextTransforms.trimTrailingWhitespaceTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "foo\nbar\nbaz")
    }

    @Test("trimming is whole-document -- it ignores the current selection's own scope entirely")
    func trimIsWholeDocumentNotSelectionScoped() {
        let text = "foo  \nbar  \nbaz  " as NSString
        let lineIndex = EditorLineIndex(text: text)
        // A caret on line 1 only -- Trim must still clean every line.
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: 0))

        let transaction = EditorTextTransforms.trimTrailingWhitespaceTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "foo\nbar\nbaz")
    }

    @Test("trimming a document with no trailing whitespace anywhere is a no-op")
    func trimNoOpWhenNothingToTrim() {
        let text = "foo\nbar\nbaz" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: 0))

        let transaction = EditorTextTransforms.trimTrailingWhitespaceTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        #expect(transaction == nil)
    }

    @Test("trimming never touches leading or internal whitespace, only trailing")
    func trimOnlyAffectsTrailingWhitespace() {
        let text = "  foo bar  " as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: 0))

        let transaction = EditorTextTransforms.trimTrailingWhitespaceTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "  foo bar")
    }

    @Test("trimming remaps a caret that sat inside the trimmed trailing whitespace to the new line end")
    func trimRemapsACaretInsideTrimmedWhitespace() {
        let text = "foo   " as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 5, length: 0)) // inside the trailing spaces

        let transaction = EditorTextTransforms.trimTrailingWhitespaceTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "foo")
        #expect(applied?.selection == NSRange(location: 3, length: 0))
    }

    @Test("trimming on a truly empty document is a no-op")
    func trimOnEmptyDocumentIsNoOp() {
        let text = "" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: 0))

        let transaction = EditorTextTransforms.trimTrailingWhitespaceTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        #expect(transaction == nil)
    }
}
