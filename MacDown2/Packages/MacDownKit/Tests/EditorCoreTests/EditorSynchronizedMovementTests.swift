import AppKit
@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 Slice 3b-iii — Synchronized plain-arrow-key caret movement
/// (§6.10). Confirmed empirically (a direct probe, before writing this
/// slice) that `NSTextView.doCommand(by:)` invokes the delegate's
/// `textView(_:doCommandBy:)` first for movement selectors — including a
/// call made directly on the text view, not just through a real key event —
/// and that a delegate returning `false` correctly falls through to
/// AppKit's own native single-caret movement afterward, so intercepting via
/// the SAME delegate method the existing E10 command hook already uses
/// (rather than inventing a new interception point) is both consistent with
/// this codebase's established pattern and verified to actually work.
@MainActor
@Suite("EditorTextSystem synchronized arrow-key movement (Slice 3b-iii)")
struct EditorSynchronizedMovementTests {
    private let support = EditingAssistIntegrationSupport.self

    // MARK: - Pure logic (direct calls, no real key event)

    @Test func moveAllCaretsRightAdvancesEveryCaretByOneCharacter() {
        let system = support.makeSystem(text: "one two three")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 0), NSRange(location: 4, length: 0)],
            primaryIndex: 0
        )

        let handled = system.moveAllCaretsRight()

        #expect(handled)
        #expect(system.selectionSet.ranges == [
            NSRange(location: 1, length: 0),
            NSRange(location: 5, length: 0),
        ])
    }

    @Test func moveAllCaretsLeftRetreatsEveryCaretByOneCharacter() {
        let system = support.makeSystem(text: "one two three")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 5, length: 0)],
            primaryIndex: 0
        )

        let handled = system.moveAllCaretsLeft()

        #expect(handled)
        #expect(system.selectionSet.ranges == [
            NSRange(location: 0, length: 0),
            NSRange(location: 4, length: 0),
        ])
    }

    @Test func moveAllCaretsLeftStopsAtDocumentStartRatherThanGoingNegative() {
        let system = support.makeSystem(text: "one two")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 0), NSRange(location: 4, length: 0)],
            primaryIndex: 0
        )

        let handled = system.moveAllCaretsLeft()

        #expect(handled)
        // The caret already at 0 stays at 0; the other moves to 3.
        #expect(system.selectionSet.ranges == [
            NSRange(location: 0, length: 0),
            NSRange(location: 3, length: 0),
        ])
    }

    @Test func moveAllCaretsRightStopsAtDocumentEnd() {
        let system = support.makeSystem(text: "one two")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 3, length: 0), NSRange(location: 7, length: 0)],
            primaryIndex: 0
        )

        let handled = system.moveAllCaretsRight()

        #expect(handled)
        #expect(system.selectionSet.ranges == [
            NSRange(location: 4, length: 0),
            NSRange(location: 7, length: 0),
        ])
    }

    @Test func moveAllCaretsLeftCollapsesARealSelectionToItsStart() {
        let system = support.makeSystem(text: "one two three")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 3), NSRange(location: 8, length: 5)],
            primaryIndex: 0
        )

        let handled = system.moveAllCaretsLeft()

        #expect(handled)
        #expect(system.selectionSet.ranges == [
            NSRange(location: 0, length: 0),
            NSRange(location: 8, length: 0),
        ])
    }

    @Test func moveAllCaretsRightCollapsesARealSelectionToItsEnd() {
        let system = support.makeSystem(text: "one two three")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 3), NSRange(location: 8, length: 5)],
            primaryIndex: 0
        )

        let handled = system.moveAllCaretsRight()

        #expect(handled)
        #expect(system.selectionSet.ranges == [
            NSRange(location: 3, length: 0),
            NSRange(location: 13, length: 0),
        ])
    }

    @Test func moveAllCaretsDownMovesEveryCaretToTheSameColumnOnTheNextLine() {
        let system = support.makeSystem(text: "one\ntwo\nthree")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 0), NSRange(location: 4, length: 0)],
            primaryIndex: 0
        )

        let handled = system.moveAllCaretsDown()

        #expect(handled)
        // Line 1 col 1 (offset 0) -> line 2 col 1 (offset 4).
        // Line 2 col 1 (offset 4) -> line 3 col 1 (offset 8).
        #expect(system.selectionSet.ranges == [
            NSRange(location: 4, length: 0),
            NSRange(location: 8, length: 0),
        ])
    }

    @Test func moveAllCaretsUpCollapsesAtTheFirstLineRatherThanGoingOutOfBounds() {
        let system = support.makeSystem(text: "one\ntwo\nthree")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        // A caret already on line 1, and a real selection on line 2.
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 4, length: 2)],
            primaryIndex: 0
        )

        let handled = system.moveAllCaretsUp()

        #expect(handled)
        // The line-1 caret can't move further and stays exactly where it
        // is; the line-2 selection collapses to its start (offset 4) and
        // moves up to line 1 at the same column (offset 0).
        #expect(system.selectionSet.ranges == [
            NSRange(location: 0, length: 0),
            NSRange(location: 1, length: 0),
        ])
    }

    @Test func convergingCaretsAfterMovementMergeIntoOne() {
        // Adversarial: a caret one character before the document end, and a
        // caret already AT the end (which `moveAllCaretsRight()` leaves in
        // place, per its own document-boundary guard), converge on the same
        // final offset once the first one advances -- `EditorSelectionSet`'s
        // own duplicate-caret merge rule must collapse them, not crash or
        // leave a stale duplicate.
        let system = support.makeSystem(text: "one two")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 6, length: 0), NSRange(location: 7, length: 0)],
            primaryIndex: 0
        )

        system.moveAllCaretsRight()

        #expect(!system.selectionSet.isMultiple)
        #expect(system.selectionSet.primaryRange == NSRange(location: 7, length: 0))
    }

    @Test func singleCaretMovementIsANoOpAtThisLevel() {
        // Fewer than two selections: this method must not intercept at all,
        // leaving the real interception decision to `doCommandBy`'s own
        // fallthrough to native handling.
        let system = support.makeSystem(text: "one two")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 3, length: 0)

        let handled = system.moveAllCaretsRight()

        #expect(!handled)
        #expect(system.selectedRange == NSRange(location: 3, length: 0), "must not itself move the single caret")
    }

    // MARK: - Real `doCommandBy` integration (the actual interception point)

    @Test func aRealMoveRightCommandSynchronizesEveryCaretWhenMultipleAreActive() {
        let system = support.makeSystem(text: "one two three")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 0), NSRange(location: 4, length: 0)],
            primaryIndex: 0
        )

        let handled = coordinator.textView(system.textView, doCommandBy: #selector(NSResponder.moveRight(_:)))

        #expect(handled)
        #expect(system.selectionSet.ranges == [
            NSRange(location: 1, length: 0),
            NSRange(location: 5, length: 0),
        ])
    }

    @Test func aRealMoveRightCommandFallsThroughToNativeHandlingForASingleCaret() {
        let system = support.makeSystem(text: "one two three")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: 0, length: 0)

        // `doCommandBy` returning `false` here means the coordinator itself
        // does not claim to have handled it; calling it through the real
        // `textView.doCommand(by:)` entry point (rather than the delegate
        // method directly) additionally proves AppKit's own native
        // single-caret movement actually runs afterward.
        system.textView.delegate = coordinator
        system.textView.doCommand(by: #selector(NSResponder.moveRight(_:)))

        #expect(system.selectedRange == NSRange(location: 1, length: 0))
    }

    @Test func markedTextSessionBypassesSynchronizedMovementEntirely() {
        let system = support.makeSystem(text: "one two three")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 0), NSRange(location: 4, length: 0)],
            primaryIndex: 0
        )
        system.textView.setMarkedText(
            "\u{3042}",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        let handled = coordinator.textView(system.textView, doCommandBy: #selector(NSResponder.moveRight(_:)))

        #expect(!handled, "an active IME composition must fail open to native handling, multi-caret or not")
    }
}
