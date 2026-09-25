import AppKit
@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 Slice 3b-ii-b — Add/Remove Cursor Above/Below (§6.10).
@MainActor
@Suite("EditorTextSystem Add Cursor Above/Below (Slice 3b-ii-b)")
struct EditorVerticalCursorTests {
    private let support = EditingAssistIntegrationSupport.self

    @Test func addCursorBelowAddsACaretAtTheSameColumnOnTheNextLine() {
        let system = support.makeSystem(text: "one two\nthree four\nfive six")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 4, length: 0) // "one |two", column 5, line 1

        let handled = system.addCursorBelow()

        #expect(handled)
        #expect(system.selectionSet.isMultiple)
        // Line 2 ("three four") column 5 -> offset 8 (start of line 2) + 4.
        let line2Start = 8
        #expect(system.selectionSet.ranges.contains(NSRange(location: line2Start + 4, length: 0)))
    }

    @Test func addCursorAboveAddsACaretAtTheSameColumnOnThePreviousLine() {
        let system = support.makeSystem(text: "one two\nthree four\nfive six")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        // Line 2 ("three four"), column 5 (offset 8 + 4 = 12).
        system.selectedRange = NSRange(location: 12, length: 0)

        let handled = system.addCursorAbove()

        #expect(handled)
        #expect(system.selectionSet.isMultiple)
        // Line 1 ("one two"), column 5 -> offset 4.
        #expect(system.selectionSet.ranges.contains(NSRange(location: 4, length: 0)))
    }

    @Test func addCursorBelowClampsToAShorterLinesActualLength() {
        let system = support.makeSystem(text: "one two three\nab\nfour five")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        // Line 1, column 10 (well past line 2's own length of 2).
        system.selectedRange = NSRange(location: 9, length: 0)

        let handled = system.addCursorBelow()

        #expect(handled)
        // Line 2 ("ab") is only 2 characters -- the new caret must clamp to
        // its end (offset 14 + 2 = 16), never past its own terminator.
        let line2Start = 14
        #expect(system.selectionSet.ranges.contains(NSRange(location: line2Start + 2, length: 0)))
    }

    @Test func addCursorAboveFromTheFirstLineIsANoOp() {
        let system = support.makeSystem(text: "one two\nthree four")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 4, length: 0)

        let handled = system.addCursorAbove()

        #expect(!handled)
        #expect(!system.selectionSet.isMultiple)
    }

    @Test func addCursorBelowFromTheLastLineIsANoOp() {
        let system = support.makeSystem(text: "one two\nthree four")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 12, length: 0) // line 2

        let handled = system.addCursorBelow()

        #expect(!handled)
        #expect(!system.selectionSet.isMultiple)
    }

    @Test func repeatedAddCursorBelowExtendsFromTheBottomMostCaretNotThePrimary() {
        // Adversarial: after the first addCursorBelow, the primary is still
        // the ORIGINAL (top) caret (`makePrimary: false`); a second call
        // must extend from the newly-added BOTTOM-most caret, not jump back
        // to the primary and re-add the same line.
        let system = support.makeSystem(text: "one\ntwo\nthree\nfour")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 0) // line 1, column 1

        system.addCursorBelow()
        system.addCursorBelow()

        #expect(system.selectionSet.count == 3)
        // Lines 1, 2, 3, all column 1: offsets 0, 4, 8.
        #expect(system.selectionSet.ranges == [
            NSRange(location: 0, length: 0),
            NSRange(location: 4, length: 0),
            NSRange(location: 8, length: 0),
        ])
    }

    @Test func repeatedAddCursorAboveExtendsFromTheTopMostCaret() {
        let system = support.makeSystem(text: "one\ntwo\nthree\nfour")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 14, length: 0) // line 4, column 1

        system.addCursorAbove()
        system.addCursorAbove()

        #expect(system.selectionSet.count == 3)
        // Lines 2, 3, 4, all column 1: offsets 4, 8, 14.
        #expect(system.selectionSet.ranges == [
            NSRange(location: 4, length: 0),
            NSRange(location: 8, length: 0),
            NSRange(location: 14, length: 0),
        ])
    }

    @Test func addCursorBelowStopsCleanlyWhenTheBottomMostCaretIsAlreadyOnTheLastLine() {
        // A multi-caret set where the bottom-most caret is already on the
        // last line must fail closed (no-op) rather than crash or add an
        // out-of-bounds caret, even though OTHER (non-bottom-most) carets
        // exist above it.
        let system = support.makeSystem(text: "one\ntwo\nthree")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 0)
        system.addCursorBelow()
        system.addCursorBelow() // now on lines 1, 2, 3 -- 3 is the last line
        #expect(system.selectionSet.count == 3)

        let handled = system.addCursorBelow()

        #expect(!handled)
        #expect(system.selectionSet.count == 3, "a no-op call must not mutate the existing carets")
    }

    @Test func addCursorBelowFromARealSelectionAnchorsOnItsEndNotItsStart() {
        // A second, later hostile review (of Slice 3b-iii) found this
        // method originally anchored on `.location` (the selection's
        // START) for BOTH directions, while the newer, more deliberate
        // `EditorTextSystem+SynchronizedMovement.swift` anchors on the END
        // for downward movement ("collapse toward the direction of
        // travel") -- producing visibly different landing columns between
        // "Add Cursor Below" and a synchronized Down-arrow press starting
        // from the same selection. Fixed to match: this test pins the
        // corrected, END-anchored behavior for `addCursorBelow`.
        //
        // A side effect of this fix: the ORIGINAL version of this test
        // exercised "the computed target point lands inside the reference
        // selection's own span," which was only reachable because the old
        // START anchor let a one-line-down target fall within a selection
        // that extended past that line. Anchoring on the END instead makes
        // that specific self-containment geometrically impossible (moving
        // one line down from a range's own END can never land before that
        // END) -- the `updated.count > selection.count` guard in
        // `addVerticalCursor` (added for the ORIGINAL hostile-review
        // finding) remains as defense in depth for a case this codebase
        // can no longer construct, not because the guard itself was wrong.
        let system = support.makeSystem(text: "one\ntwo\nthree\nfour")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        // A single real selection spanning lines 1-3 ("one\ntwo\nth"), END
        // at offset 9 (line 3, column 2).
        system.selectedRange = NSRange(location: 0, length: 9)

        let handled = system.addCursorBelow()

        #expect(handled)
        // Line 3 column 2 (the selection's end) -> line 4 column 2 -> "four"
        // starting at offset 14, column 2 is offset 15.
        #expect(system.selectionSet.ranges == [
            NSRange(location: 0, length: 9),
            NSRange(location: 15, length: 0),
        ])
    }

    @Test func addCursorBelowHandlesCJKAndEmojiColumnsCorrectly() {
        // §6.10's own adversarial coverage note: CJK/emoji columns.
        // `EditorLineIndex` counts grapheme clusters, not UTF-16 units, for
        // columns -- an emoji (2 UTF-16 units) must still count as one
        // column, matching every other user-facing position in this editor.
        let system = support.makeSystem(text: "a😀b\nxyz")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        // Column 3 on line 1 ("a😀|b") -- after "a" (1) and the emoji (1
        // grapheme cluster, 2 UTF-16 units) -- UTF-16 offset 3.
        system.selectedRange = NSRange(location: 3, length: 0)

        let handled = system.addCursorBelow()

        #expect(handled)
        // Line 2 ("xyz") starts at UTF-16 offset 5 (1 + 2 + 1 + 1 = "a"(1) +
        // emoji(2) + "b"(1) + "\n"(1)); column 3 there is offset 5 + 2 = 7.
        #expect(system.selectionSet.ranges.contains(NSRange(location: 7, length: 0)))
    }
}
