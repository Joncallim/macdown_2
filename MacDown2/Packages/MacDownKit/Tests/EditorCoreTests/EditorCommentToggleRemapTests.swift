@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 §6.13, Slice 4c-iii — Toggle Comment's own resulting-selection
/// and blank-line tests, split out of `EditorCommentToggleTests.swift` to
/// stay under swiftlint's type-body-length/file-length limits once the P1/
/// P2 regression tests were also added there.
@Suite("EditorCommentToggle — resulting selection and blank lines (Slice 4c-iii)")
struct EditorCommentToggleRemapTests {
    private let swiftProfile = LanguageEditingProfileRegistry.profile(for: "swift")

    // MARK: - Resulting selection (a P1 an independent hostile review found)

    @Test("a caret INSIDE a line's own leading whitespace stays exactly where it was after commenting")
    func commentingLeavesACaretInsideLeadingWhitespaceUnmoved() {
        // The exact P1: reusing `MarkdownEditingAssistEngine.remappedSelection`
        // (whose own "at column 0, unaffected" special case only covers
        // column 0) wrongly applied the WHOLE line's own insert delta to a
        // caret sitting strictly INSIDE the leading whitespace (column 1 of
        // 2), teleporting it from column 1 to column 4 -- past the newly
        // inserted "// " -- instead of leaving it at column 1, which is
        // strictly BEFORE where the edit actually happens (after the
        // leading whitespace).
        let text = "  foo" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 1, length: 0)) // between the two leading spaces

        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: false,
            profile: swiftProfile
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "  // foo")
        #expect(applied?.selection == NSRange(location: 1, length: 0))
    }

    @Test("a caret INSIDE a line's own leading whitespace stays exactly where it was after uncommenting")
    func uncommentingLeavesACaretInsideLeadingWhitespaceUnmoved() {
        let text = "  // foo" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 1, length: 0)) // between the two leading spaces

        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: false,
            profile: swiftProfile
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "  foo")
        #expect(applied?.selection == NSRange(location: 1, length: 0))
    }

    @Test("a caret AFTER the inserted prefix shifts by the prefix's own length, not the whole line's")
    func commentingShiftsACaretAfterTheInsertionPointByThePrefixLength() {
        let text = "foo" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 1, length: 0)) // after "f"

        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: false,
            profile: swiftProfile
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "// foo")
        // "// " is 3 UTF-16 units; the caret was at column 1 (after "f",
        // which is now preceded by the prefix), so it lands at 1 + 3 = 4.
        #expect(applied?.selection == NSRange(location: 4, length: 0))
    }

    @Test("commenting a two-line selection correctly remaps a second-line caret through both lines' own deltas")
    func commentingRemapsASecondLineCaretThroughBothLinesOwnDeltas() {
        let text = "foo\n  bar" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: false,
            profile: swiftProfile
        )
        #expect(transaction?.replacements.count == 1)
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "// foo\n  // bar")
    }

    @Test("two carets on adjacent lines merge into one group; the SECOND caret's own delta stacks on the first's")
    func commentingRemapsEachAdjacentCaretThroughTheGroupsCumulativeShift() {
        // Unlike the whole-selection test above (which never asserts on the
        // resulting SELECTION at all, only text), this uses two distinct
        // bare carets -- one per line -- that merge into a single 2-line
        // group (adjacent lines merge, §6.13), so each member's own
        // resulting position must be independently correct: the first
        // caret shifts by its own line's delta; the second must ALSO
        // account for the first line's already-applied delta before
        // resolving its OWN column against ITS OWN insertion point.
        let text = "foo\n  bar" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 7, length: 0)], // after "f", after "b"
            primaryIndex: 0
        )

        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: false,
            profile: swiftProfile
        )
        #expect(transaction?.replacements.count == 1)
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "// foo\n  // bar")
        #expect(transaction?.resultingSelection?.ranges == [
            NSRange(location: 4, length: 0), // "// f|oo" -- after "f"
            NSRange(location: 13, length: 0), // "  // b|ar" -- after "b"
        ])
    }

    @Test("uncommenting a caret INSIDE the comment marker itself clamps to the insertion point, not before it")
    func uncommentingClampsACaretInsideTheDelimiterToTheInsertionPoint() {
        // A P2 an independent hostile review found in the P1 fix's own
        // first draft: a position strictly inside the just-removed prefix
        // (e.g. between the two "/" characters of "//") isn't "after the
        // edit" in any meaningful sense -- applying the removal's full
        // negative delta landed it BEFORE the line's own leading
        // whitespace, further from correct than doing nothing. It now
        // clamps to the insertion point itself (where the removed prefix
        // used to start), matching where a reasonable person would expect
        // the caret to end up once the thing it was inside no longer exists.
        let text = "  // foo" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 3, length: 0)) // between the two "/"

        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: false,
            profile: swiftProfile
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "  foo")
        #expect(applied?.selection == NSRange(location: 2, length: 0)) // right after the leading whitespace
    }

    // MARK: - Blank lines (a P2 an independent hostile review found)

    @Test("a block that's fully commented except for one BLANK line still uncomments as a whole")
    func uncommentsFullyDespiteOneBlankLine() {
        // A P2 an independent hostile review found in an earlier version:
        // folding blank lines into the "already commented?" decision meant
        // a block where every REAL line was already commented, but one line
        // was blank, wrongly registered as "not all commented" -- so
        // pressing the shortcut on a block that visibly looked fully
        // commented added a SECOND, redundant prefix to every already-
        // commented line instead of stripping them. Blank lines are now
        // ignored for the decision AND left untouched by the action.
        let text = "// foo\n\n// bar" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: false,
            profile: swiftProfile
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "foo\n\nbar")
    }

    @Test("commenting a block with a blank line in it leaves the blank line untouched")
    func commentingLeavesABlankLineUntouched() {
        let text = "foo\n\nbar" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 0, length: text.length))

        let transaction = EditorCommentToggle.toggleCommentTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection,
            isMarkdownFormat: false,
            profile: swiftProfile
        )
        let applied = LineTransformTestSupport.applied(transaction, to: text as String)

        #expect(applied?.text == "// foo\n\n// bar")
    }
}
