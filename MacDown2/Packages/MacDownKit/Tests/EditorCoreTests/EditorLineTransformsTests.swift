@testable import EditorCore
import Foundation
import Testing

/// Applies an `EditorEditTransaction`'s replacements to a plain `String`
/// (highest-offset-to-lowest, mirroring `EditorTextSystem.apply(_:)`'s own
/// application order) without needing a mounted `NSTextView` — these
/// transforms' own logic is pure, so their tests should be too.
enum LineTransformTestSupport {
    static func applied(_ transaction: EditorEditTransaction?, to text: String) -> (text: String, selection: NSRange)? {
        guard let transaction else { return nil }
        var result = text as NSString
        let ordered = transaction.replacements.sorted { $0.range.location > $1.range.location }
        for replacement in ordered {
            result = result.replacingCharacters(in: replacement.range, with: replacement.replacementText) as NSString
        }
        return (result as String, transaction.resultingSelection?.primaryRange ?? NSRange(location: 0, length: 0))
    }
}

/// EPIC-22 §6.13, Slice 4c-i — pure-logic tests for the four line-reordering
/// transforms, entirely independent of `NSTextView`.
@Suite("EditorLineTransforms (Slice 4c-i)")
struct EditorLineTransformsTests {
    // MARK: - Duplicate Line

    @Test("duplicating a single line inserts a copy immediately after it, caret follows")
    func duplicateSingleLine() {
        let text = "AAA\nBBB\nCCC" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let caret = text.range(of: "BBB").location + 1 // inside "BBB", after 'B'
        let selection = EditorSelectionSet(single: NSRange(location: caret, length: 0))

        let transaction = EditorLineTransforms.duplicateLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "AAA\nBBB\nBBB\nCCC")
        #expect(applied?.selection == NSRange(location: 9, length: 0)) // same column, on the duplicate (second "BBB")
    }

    @Test("duplicating the document's actual last line (no trailing newline) inserts its own separator")
    func duplicateLastLineWithNoTrailingNewline() {
        let text = "AAA\nBBB" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let caret = text.length // end of "BBB"
        let selection = EditorSelectionSet(single: NSRange(location: caret, length: 0))

        let transaction = EditorLineTransforms.duplicateLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "AAA\nBBB\nBBB")
    }

    @Test("duplicating a multi-line selection duplicates the whole block")
    func duplicateMultiLineBlock() {
        let text = "AAA\nBBB\nCCC\nDDD" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 4, length: 7)) // "BBB\nCCC"

        let transaction = EditorLineTransforms.duplicateLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "AAA\nBBB\nCCC\nBBB\nCCC\nDDD")
    }

    @Test("two carets on the same line merge into one group and both land on the duplicate")
    func duplicateTwoCaretsSameLineMerge() {
        let text = "AAA\nBBBBB\nCCC" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: 5, length: 0), NSRange(location: 8, length: 0)], // both inside "BBBBB"
            primaryIndex: 0
        )

        let transaction = EditorLineTransforms.duplicateLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        #expect(transaction?.replacements.count == 1) // merged into one group, one replacement
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)
        #expect(applied?.text == "AAA\nBBBBB\nBBBBB\nCCC")
    }

    // MARK: - Delete Line

    @Test("deleting a single line removes it and its own terminator")
    func deleteSingleLine() {
        let text = "AAA\nBBB\nCCC" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let caret = text.range(of: "BBB").location
        let selection = EditorSelectionSet(single: NSRange(location: caret, length: 0))

        let transaction = EditorLineTransforms.deleteLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "AAA\nCCC")
        #expect(applied?.selection == NSRange(location: 4, length: 0))
    }

    @Test("deleting the document's actual last line also swallows the preceding line's own terminator")
    func deleteLastLineSwallowsPrecedingTerminator() {
        let text = "AAA\nBBB" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let caret = text.length
        let selection = EditorSelectionSet(single: NSRange(location: caret, length: 0))

        let transaction = EditorLineTransforms.deleteLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "AAA") // no dangling trailing newline
        #expect(applied?.selection == NSRange(location: 3, length: 0))
    }

    @Test("deleting the only line in a single-line document empties it")
    func deleteOnlyLine() {
        let text = "AAA" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 1, length: 0))

        let transaction = EditorLineTransforms.deleteLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "")
        #expect(applied?.selection == NSRange(location: 0, length: 0))
    }

    @Test("deleting lines on a truly empty document is a no-op, not a spurious zero-length edit")
    func deleteLinesOnEmptyDocumentIsNoOp() {
        let text = "" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: 0))

        let transaction = EditorLineTransforms.deleteLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        #expect(transaction == nil)
    }

    @Test("deleting two disjoint lines removes both in one transaction")
    func deleteTwoDisjointLines() {
        let text = "AAA\nBBB\nCCC\nDDD" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 0), NSRange(location: 8, length: 0)], // "AAA" and "CCC"
            primaryIndex: 0
        )

        let transaction = EditorLineTransforms.deleteLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        #expect(transaction?.replacements.count == 2)
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)
        #expect(applied?.text == "BBB\nDDD")
    }

    // MARK: - Join Lines

    @Test("joining two lines merges them with a single space, stripping the joined-in line's leading whitespace")
    func joinTwoLines() {
        let text = "foo\n  bar" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: 0))

        let transaction = EditorLineTransforms.joinLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "foo bar")
        #expect(applied?.selection == NSRange(location: 3, length: 0)) // at the join point
    }

    @Test("joining a multi-line selection merges every touched line into one")
    func joinMultipleLines() {
        let text = "AAA\nBBB\nCCC" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorLineTransforms.joinLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "AAA BBB CCC")
    }

    @Test("joining a caret already on the document's only line is a no-op")
    func joinSingleLineIsNoOp() {
        let text = "AAA" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 1, length: 0))

        let transaction = EditorLineTransforms.joinLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        #expect(transaction == nil)
    }

    @Test("joining never pulls in content after the block")
    func joinDoesNotTouchFollowingContent() {
        let text = "AAA\nBBB\nCCC" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: 4)) // "AAA\n" -- spans lines 1-2

        let transaction = EditorLineTransforms.joinLinesTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "AAA BBB\nCCC")
    }
}
