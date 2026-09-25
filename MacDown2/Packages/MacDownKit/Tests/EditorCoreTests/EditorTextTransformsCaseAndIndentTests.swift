@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 §6.13, Slice 4c-ii — pure-logic tests for Convert Case and
/// Increase/Decrease Indent, split out of `EditorTextTransformsTests.swift`
/// to stay under swiftlint's type-body-length limit once Sort/Dedupe/Trim
/// were also added there.
@Suite("EditorTextTransforms — Case and Indent (Slice 4c-ii)")
struct EditorTextTransformsCaseAndIndentTests {
    // MARK: - Convert Case

    @Test("uppercase converts the selected text")
    func uppercaseBasic() {
        let text = "hello world" as NSString
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorTextTransforms.convertCaseTransaction(
            text: text,
            selection: selection,
            conversion: .uppercase
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "HELLO WORLD")
    }

    @Test("lowercase converts the selected text")
    func lowercaseBasic() {
        let text = "HELLO WORLD" as NSString
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorTextTransforms.convertCaseTransaction(
            text: text,
            selection: selection,
            conversion: .lowercase
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "hello world")
    }

    @Test("capitalized title-cases each word")
    func capitalizedBasic() {
        let text = "hello world" as NSString
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorTextTransforms.convertCaseTransaction(
            text: text,
            selection: selection,
            conversion: .capitalized
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "Hello World")
    }

    @Test("case conversion declines entirely when any active selection is empty")
    func caseConversionDeclinesOnAnyEmptySelection() {
        let text = "hello world" as NSString
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 5), NSRange(location: 6, length: 0)], // "hello" + a bare caret
            primaryIndex: 0
        )

        let transaction = EditorTextTransforms.convertCaseTransaction(
            text: text,
            selection: selection,
            conversion: .uppercase
        )
        #expect(transaction == nil)
    }

    @Test("case conversion applies independently to multiple non-empty selections in one transaction")
    func caseConversionMultipleSelections() {
        let text = "cat and dog" as NSString
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 3), NSRange(location: 8, length: 3)], // "cat", "dog"
            primaryIndex: 0
        )

        let transaction = EditorTextTransforms.convertCaseTransaction(
            text: text,
            selection: selection,
            conversion: .uppercase
        )
        #expect(transaction?.replacements.count == 2)
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)
        #expect(applied?.text == "CAT and DOG")
    }

    @Test("case conversion correctly handles a length-changing uppercase (German ß -> SS)")
    func caseConversionHandlesLengthChangingUppercase() throws {
        let text = "straße" as NSString
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorTextTransforms.convertCaseTransaction(
            text: text,
            selection: selection,
            conversion: .uppercase
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "STRASSE")
        #expect(try applied?.selection == NSRange(location: 0, length: (#require(applied?.text) as NSString).length))
    }

    // MARK: - Increase / Decrease Indent

    @Test("increase indent adds width spaces to every line the selection touches")
    func increaseIndentBasic() {
        let text = "foo\nbar" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorTextTransforms.indentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            width: 4,
            decrease: false
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "    foo\n    bar")
    }

    @Test("decrease indent removes up to width leading spaces from every touched line")
    func decreaseIndentBasic() {
        let text = "    foo\n    bar" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorTextTransforms.indentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            width: 4,
            decrease: true
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "foo\nbar")
    }

    @Test("increase indent works for a bare caret, indenting its own current line")
    func increaseIndentBareCaret() {
        let text = "foo" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 1, length: 0))

        let transaction = EditorTextTransforms.indentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            width: 2,
            decrease: false
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "  foo")
        // A P1 an independent hostile review found: an earlier version of
        // this method fed the whole line-block into `indentSelectedLines`/
        // `unindentSelectedLines` and propagated THEIR OWN resultingSelection
        // (the whole block) straight through, so a bare caret ended up with
        // the entire re-indented line SELECTED rather than a collapsed
        // caret -- meaning the very next keystroke would replace the whole
        // line. The caret was originally after "f" (offset 1); after
        // prepending 2 spaces, it must still be a bare caret, now after
        // "f" in "  foo" (offset 1 + 2 = 3), never a real selection.
        #expect(applied?.selection == NSRange(location: 3, length: 0))
    }

    @Test("decrease indent on an already-flush line is a genuine no-op")
    func decreaseIndentNoOpWhenAlreadyFlush() {
        let text = "foo" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: 0))

        let transaction = EditorTextTransforms.indentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            width: 4,
            decrease: true
        )
        #expect(transaction == nil)
    }

    @Test("two carets on the same line merge into one group -- indenting it exactly once, not twice")
    func indentMergesTwoCaretsOnTheSameLine() {
        let text = "foobar" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 4, length: 0)],
            primaryIndex: 0
        )

        let transaction = EditorTextTransforms.indentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            width: 2,
            decrease: false
        )
        #expect(transaction?.replacements.count == 1)
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)
        #expect(applied?.text == "  foobar")
    }

    @Test("increase indent on multiple disjoint selections indents each independently")
    func increaseIndentMultipleDisjointSelections() {
        let text = "foo\nbar\nbaz" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 0), NSRange(location: 8, length: 0)], // line 1, line 3
            primaryIndex: 0
        )

        let transaction = EditorTextTransforms.indentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            width: 2,
            decrease: false
        )
        #expect(transaction?.replacements.count == 2)
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)
        #expect(applied?.text == "  foo\nbar\n  baz")
        // Each disjoint caret must independently remain a bare caret (not
        // expand into a selection). A caret sitting EXACTLY at a line's own
        // start is not shifted by that same line's own indent delta
        // (`remappedLocation`'s own established convention, already used by
        // single-selection Tab/Shift-Tab: the caret stays BEFORE the newly
        // inserted indentation) -- so the first caret stays at 0. The
        // second group's own remapping must ALSO correctly account for
        // both its own group's absolute start offset (8, not 0 -- the
        // exact P1 this test's own fix commit corrected: an earlier
        // version added only the cross-group `delta` and forgot the
        // group's own `groupRange.location`) and the first group's already-
        // applied delta (+2).
        #expect(transaction?.resultingSelection?.ranges == [
            NSRange(location: 0, length: 0), // "  foo", caret stays before the inserted indent
            NSRange(location: 10, length: 0), // "  foo\nbar\n  baz", caret stays before the inserted indent
        ])
    }

    @Test("two bare carets on adjacent lines merge into one group; each keeps its own caret, not one merged selection")
    func indentMergedGroupPreservesEachMembersOwnCaret() {
        // The specific multi-caret scenario the same hostile review traced
        // through by hand: two carets on ADJACENT lines merge into one
        // `EditorLineTransforms` group (§6.13's own conflict rule), but
        // unlike the P1 this pins a fix for, each member is remapped
        // independently through the group's own per-line deltas -- neither
        // caret should vanish or expand into a selection.
        let text = "foo\nbar" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 5, length: 0)], // after "f", after "b"
            primaryIndex: 0
        )

        let transaction = EditorTextTransforms.indentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            width: 2,
            decrease: false
        )
        #expect(transaction?.replacements.count == 1) // one merged group, one replacement
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)
        #expect(applied?.text == "  foo\n  bar")
        #expect(transaction?.resultingSelection?.ranges == [
            NSRange(location: 3, length: 0), // after "f" in "  foo"
            NSRange(location: 9, length: 0), // after "b" in "  bar"
        ])
    }
}
