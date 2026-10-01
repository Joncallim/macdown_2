@testable import EditorCore
import Foundation
import Testing

/// #183 F12 — a selection set mixing multi-line groups with single-line ones
/// must transform the multi-line groups, not reject the whole command.
@Suite("EditorTextTransforms mixed selection groups (#183 F12)")
struct EditorTextTransformsMixedSelectionTests {
    @Test func sortTransformsMultiLineGroupsAndLeavesASingleLineCaretAlone() throws {
        let text = "zz\naa\nmm\nxx\nkk\nyy\nbb" as NSString
        let selection = EditorSelectionSet(
            ranges: [
                NSRange(location: 0, length: 5),
                NSRange(location: 10, length: 0),
                NSRange(location: 15, length: 5),
            ],
            primaryIndex: 1
        )

        let transaction = try #require(EditorTextTransforms.sortLinesTransaction(
            text: text,
            lineIndex: EditorLineIndex(text: text),
            selection: selection
        ))
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "aa\nzz\nmm\nxx\nkk\nbb\nyy")
        let resulting = try #require(transaction.resultingSelection)
        #expect(resulting.ranges.count == 3)
        #expect(resulting.ranges[1] == NSRange(location: 10, length: 0))
        #expect(resulting.primaryIndex == 1)
    }

    @Test func dedupeShiftsTheUntouchedSingleLineSelectionByEarlierDeletions() throws {
        let text = "a\na\nx\nb" as NSString
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 3), NSRange(location: 6, length: 0)],
            primaryIndex: 0
        )

        let transaction = try #require(EditorTextTransforms.dedupeLinesTransaction(
            text: text,
            lineIndex: EditorLineIndex(text: text),
            selection: selection
        ))
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "a\nx\nb")
        #expect(try #require(transaction.resultingSelection).ranges[1] == NSRange(location: 4, length: 0))
    }

    @Test func aSelectionSetOfOnlySingleLineGroupsIsStillANoOp() {
        let text = "b\nx\na" as NSString
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 0), NSRange(location: 4, length: 0)],
            primaryIndex: 0
        )

        #expect(EditorTextTransforms.sortLinesTransaction(
            text: text,
            lineIndex: EditorLineIndex(text: text),
            selection: selection
        ) == nil)
    }
}

/// #183 F02 — Remove Duplicate Lines is exact, not canonical.
@Suite("EditorTextTransforms exact dedupe (#183 F02)")
struct EditorTextTransformsExactDedupeTests {
    @Test func canonicallyEquivalentButScalarDistinctLinesAreBothKept() throws {
        let text = "\u{212B}\n\u{00C5}\n\u{00C5}" as NSString
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = try #require(EditorTextTransforms.dedupeLinesTransaction(
            text: text,
            lineIndex: EditorLineIndex(text: text),
            selection: selection
        ))
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text.unicodeScalars.map(\.value) == [0x212B, 0x0A, 0x00C5])
    }
}
