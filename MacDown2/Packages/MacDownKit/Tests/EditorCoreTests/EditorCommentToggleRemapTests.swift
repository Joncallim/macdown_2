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
