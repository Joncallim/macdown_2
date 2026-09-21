import AppKit
@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 Slice 1 — `EditorEditTransaction` is the generalized "one
/// command, one undo group, one publication" primitive multi-cursor editing
/// (and any future N-range command) funnels through. These tests exercise
/// it against a real mounted `NSTextView`/`EditorTextSystem`, matching
/// `JSONFormattingUndoPublicationTests`' existing integration style, since
/// undo-grouping/publication-count behavior only manifests with a real
/// AppKit text view and window.
@MainActor
@Suite("EditorEditTransaction")
struct EditorEditTransactionTests {
    private let support = EditingAssistIntegrationSupport.self

    @Test func singleReplacementUpdatesText() {
        let system = support.makeSystem(text: "hello world")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        system.apply(EditorEditTransaction(replacements: [
            TextReplacement(range: NSRange(location: 6, length: 5), replacementText: "there"),
        ]))

        #expect(system.text == "hello there")
    }

    @Test func multiRangeReplacementAppliesToEveryRange() {
        let system = support.makeSystem(text: "cat cat cat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        // Three occurrences of "cat", replaced highest-offset-first so
        // earlier offsets are never invalidated by a later replacement.
        system.apply(EditorEditTransaction(replacements: [
            TextReplacement(range: NSRange(location: 0, length: 3), replacementText: "dog"),
            TextReplacement(range: NSRange(location: 4, length: 3), replacementText: "dog"),
            TextReplacement(range: NSRange(location: 8, length: 3), replacementText: "dog"),
        ]))

        #expect(system.text == "dog dog dog")
    }

    @Test func multiRangeIsOneUndoStepAndOnePublication() {
        let system = support.makeSystem(text: "a a a")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)
        let (binding, counter) = support.makeBinding()
        coordinator.textBinding = binding

        system.apply(EditorEditTransaction(
            replacements: [
                TextReplacement(range: NSRange(location: 0, length: 1), replacementText: "X"),
                TextReplacement(range: NSRange(location: 2, length: 1), replacementText: "X"),
                TextReplacement(range: NSRange(location: 4, length: 1), replacementText: "X"),
            ],
            undoActionName: "Replace All"
        ))

        #expect(system.text == "X X X")
        #expect(counter.count == 1, "expected exactly one binding publication for a 3-range edit, got \(counter.count)")
        #expect(system.undoManager.canUndo)

        // One undo reverts ALL three replacements together, not one at a time.
        system.undoManager.undo()
        #expect(system.text == "a a a")
    }

    @Test func resultingSelectionIsInstalledPostEdit() {
        let system = support.makeSystem(text: "cat cat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        let resultingSelection = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3)],
            primaryIndex: 0
        )
        system.apply(EditorEditTransaction(
            replacements: [
                TextReplacement(range: NSRange(location: 0, length: 3), replacementText: "dog"),
                TextReplacement(range: NSRange(location: 4, length: 3), replacementText: "dog"),
            ],
            resultingSelection: resultingSelection
        ))

        #expect(system.textView.selectedRanges.map(\.rangeValue) == resultingSelection.ranges)
    }

    @Test func emptyTransactionIsANoOp() {
        let system = support.makeSystem(text: "unchanged")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        system.apply(EditorEditTransaction(replacements: []))

        #expect(system.text == "unchanged")
        #expect(!system.undoManager.canUndo)
    }

    // MARK: - `validate(_:documentLength:)` (pure, no AppKit)

    /// Unlike `apply(_:)` itself (whose `assertionFailure` on invalid input
    /// traps in a normal Debug test run), this pure validation logic can be
    /// exercised directly against genuinely malformed input in any build
    /// configuration. A transaction is one atomic command: validity is
    /// all-or-nothing for the whole set, never a partial "safe prefix" --
    /// see `malformedTransactionMutatesNothing` below for the corresponding
    /// AppKit-level, all-or-nothing regression.
    @Test func validateAcceptsASingleValidReplacement() {
        let replacements = [
            TextReplacement(range: NSRange(location: 2, length: 3), replacementText: "dog"),
        ]
        #expect(EditorEditTransaction.validate(replacements, documentLength: 11))
    }

    @Test func validateAcceptsTwoDisjointReplacements() {
        let replacements = [
            TextReplacement(range: NSRange(location: 6, length: 2), replacementText: "X"),
            TextReplacement(range: NSRange(location: 0, length: 2), replacementText: "Y"),
        ]
        #expect(EditorEditTransaction.validate(replacements, documentLength: 10))
    }

    @Test func validateAcceptsAllNonOverlappingInBoundsReplacements() {
        let replacements = [
            TextReplacement(range: NSRange(location: 8, length: 3), replacementText: "dog"),
            TextReplacement(range: NSRange(location: 4, length: 3), replacementText: "dog"),
            TextReplacement(range: NSRange(location: 0, length: 3), replacementText: "dog"),
        ]
        #expect(EditorEditTransaction.validate(replacements, documentLength: 11))
    }

    @Test func validateAcceptsTouchingRanges() {
        // [0,5) and [5,5) touch but do not overlap -- must remain valid.
        let replacements = [
            TextReplacement(range: NSRange(location: 0, length: 5), replacementText: "X"),
            TextReplacement(range: NSRange(location: 5, length: 5), replacementText: "Y"),
        ]
        #expect(EditorEditTransaction.validate(replacements, documentLength: 10))
    }

    @Test func validateAcceptsDistinctZeroLengthCarets() {
        // Two zero-length inserts at DIFFERENT locations are ordinary
        // multi-cursor typing, not a duplicate-edit ambiguity.
        let replacements = [
            TextReplacement(range: NSRange(location: 0, length: 0), replacementText: "x"),
            TextReplacement(range: NSRange(location: 5, length: 0), replacementText: "x"),
        ]
        #expect(EditorEditTransaction.validate(replacements, documentLength: 10))
    }

    @Test func validateRejectsTheWholeSetOnAnyOverlap() {
        // [4,3) and [2,3) overlap (2+3=5 > 4); the valid [8,3) entry must
        // NOT survive either -- validity is all-or-nothing. The overlapping
        // pair is the FIRST pair in sorted order (2,3)/(4,3).
        let replacements = [
            TextReplacement(range: NSRange(location: 8, length: 3), replacementText: "ok"),
            TextReplacement(range: NSRange(location: 4, length: 3), replacementText: "X"),
            TextReplacement(range: NSRange(location: 2, length: 3), replacementText: "Y"),
        ]
        #expect(!EditorEditTransaction.validate(replacements, documentLength: 11))
    }

    @Test func validateRejectsAnOverlapInTheMiddleOfSortedOrder() {
        // Sorted: (0,2), (2,2), (3,2), (10,2). Only the middle pair
        // -- (2,2)/(3,2), since 3 < 2+2=4 -- overlaps; the pairs on
        // either side of it are fine.
        let replacements = [
            TextReplacement(range: NSRange(location: 0, length: 2), replacementText: "a"),
            TextReplacement(range: NSRange(location: 2, length: 2), replacementText: "b"),
            TextReplacement(range: NSRange(location: 3, length: 2), replacementText: "c"),
            TextReplacement(range: NSRange(location: 10, length: 2), replacementText: "d"),
        ]
        #expect(!EditorEditTransaction.validate(replacements, documentLength: 20))
    }

    @Test func validateRejectsAnOverlapAtTheEndOfSortedOrder() {
        // Sorted: (0,2), (5,2), (10,2), (11,2). Only the LAST pair
        // -- (10,2)/(11,2), since 11 < 10+2=12 -- overlaps.
        let replacements = [
            TextReplacement(range: NSRange(location: 0, length: 2), replacementText: "a"),
            TextReplacement(range: NSRange(location: 5, length: 2), replacementText: "b"),
            TextReplacement(range: NSRange(location: 10, length: 2), replacementText: "c"),
            TextReplacement(range: NSRange(location: 11, length: 2), replacementText: "d"),
        ]
        #expect(!EditorEditTransaction.validate(replacements, documentLength: 20))
    }

    @Test func validateRejectsAnOutOfBoundsReplacement() {
        let replacements = [
            TextReplacement(range: NSRange(location: 5, length: 10), replacementText: "X"),
        ]
        #expect(!EditorEditTransaction.validate(replacements, documentLength: 8))
    }

    @Test func validateRejectsTheWholeSetWhenOneEntryIsOutOfBounds() {
        // The out-of-bounds entry sorts FIRST (lowest offset); the higher,
        // valid one must still be rejected along with it -- no partial
        // result.
        let replacements = [
            TextReplacement(range: NSRange(location: 5, length: 2), replacementText: "ok"),
            TextReplacement(range: NSRange(location: -1, length: 1), replacementText: "bad"),
        ]
        #expect(!EditorEditTransaction.validate(replacements, documentLength: 8))
    }

    @Test func validateRejectsAnOutOfBoundsEntryInTheMiddleOfAnOtherwiseValidSet() {
        // Sorted: (0,2), (3,20), (8,2). Only the middle entry is out of
        // bounds (3+20=23 > 10); the other two, on their own, are fine.
        let replacements = [
            TextReplacement(range: NSRange(location: 0, length: 2), replacementText: "a"),
            TextReplacement(range: NSRange(location: 3, length: 20), replacementText: "bad"),
            TextReplacement(range: NSRange(location: 8, length: 2), replacementText: "c"),
        ]
        #expect(!EditorEditTransaction.validate(replacements, documentLength: 10))
    }

    @Test func validateRejectsAnOutOfBoundsEntryLastInSortedOrder() {
        let replacements = [
            TextReplacement(range: NSRange(location: 0, length: 2), replacementText: "a"),
            TextReplacement(range: NSRange(location: 5, length: 2), replacementText: "b"),
            TextReplacement(range: NSRange(location: 18, length: 10), replacementText: "bad"),
        ]
        #expect(!EditorEditTransaction.validate(replacements, documentLength: 20))
    }

    @Test func validateRejectsLocationLengthOverflow() {
        // NSRange stores platform-native Int fields, so a malicious/buggy
        // caller can construct a location/length pair whose sum overflows
        // Int.max -- `addingReportingOverflow` must catch this rather than
        // trapping or wrapping.
        let replacements = [
            TextReplacement(range: NSRange(location: Int.max, length: 1), replacementText: "X"),
        ]
        #expect(!EditorEditTransaction.validate(replacements, documentLength: 10))
    }

    @Test func validateRejectsANegativeLocation() {
        let replacements = [
            TextReplacement(range: NSRange(location: -1, length: 1), replacementText: "X"),
        ]
        #expect(!EditorEditTransaction.validate(replacements, documentLength: 10))
    }

    @Test func validateRejectsANegativeLength() {
        let replacements = [
            TextReplacement(range: NSRange(location: 2, length: -1), replacementText: "X"),
        ]
        #expect(!EditorEditTransaction.validate(replacements, documentLength: 10))
    }

    @Test func validateRejectsDuplicateZeroLengthEditsAtTheSameLocation() {
        let replacements = [
            TextReplacement(range: NSRange(location: 5, length: 0), replacementText: "x"),
            TextReplacement(range: NSRange(location: 5, length: 0), replacementText: "y"),
        ]
        #expect(!EditorEditTransaction.validate(replacements, documentLength: 10))
    }

    @Test func validateAcceptsAnEmptySet() {
        #expect(EditorEditTransaction.validate([], documentLength: 10))
    }

    // MARK: - Malformed transaction, mounted `NSTextView` (AppKit-level regression)

    /// The all-or-nothing contract at the level that actually matters: a
    /// malformed transaction applied against a real mounted text view must
    /// leave text, selection, undo state, AND publication count completely
    /// untouched -- not partially applied. Uses the internal
    /// `reportsInvalidAsAssertionFailure: false` seam so this
    /// runs to completion under a normal Debug `swift test` -- the real
    /// `apply(_:)` entry point every production call site uses always
    /// reports `true` and cannot be told otherwise from outside this
    /// module; see that method's doc comment for why.
    @Test func malformedTransactionMutatesNothing() {
        let system = support.makeSystem(text: "cat cat cat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)
        let (binding, counter) = support.makeBinding()
        coordinator.textBinding = binding
        let selectionBefore = system.textView.selectedRanges

        // The first two entries are individually valid and would, on their
        // own, succeed -- only the third (out of bounds) is malformed. The
        // whole transaction must still be rejected, not just that entry.
        system.apply(
            EditorEditTransaction(
                replacements: [
                    TextReplacement(range: NSRange(location: 8, length: 3), replacementText: "dog"),
                    TextReplacement(range: NSRange(location: 4, length: 3), replacementText: "dog"),
                    TextReplacement(range: NSRange(location: 100, length: 3), replacementText: "dog"),
                ],
                undoActionName: "Replace All"
            ),
            reportsInvalidAsAssertionFailure: false
        )

        #expect(system.text == "cat cat cat", "malformed transaction must not mutate any text, including valid members")
        #expect(
            system.textView.selectedRanges == selectionBefore,
            "malformed transaction must not change the selection"
        )
        #expect(!system.undoManager.canUndo, "malformed transaction must not create an undo entry")
        // swiftlint:disable:next empty_count
        #expect(counter.count == 0, "malformed transaction must not publish the binding at all")
    }

    @Test func malformedTransactionWithDuplicateZeroLengthEditsMutatesNothing() {
        let system = support.makeSystem(text: "unchanged")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)
        let (binding, counter) = support.makeBinding()
        coordinator.textBinding = binding

        system.apply(
            EditorEditTransaction(replacements: [
                TextReplacement(range: NSRange(location: 3, length: 0), replacementText: "x"),
                TextReplacement(range: NSRange(location: 3, length: 0), replacementText: "y"),
            ]),
            reportsInvalidAsAssertionFailure: false
        )

        #expect(system.text == "unchanged")
        #expect(!system.undoManager.canUndo)
        // swiftlint:disable:next empty_count
        #expect(counter.count == 0)
    }

    @Test func hundredCaretInsertionAppliesToAll() {
        // Adversarial: 100+ simultaneous cursors, per the epic's explicit
        // "100+ cursors" requirement.
        let original = String(repeating: "x", count: 100)
        let system = support.makeSystem(text: original)
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        let replacements = (0 ..< 100).map { TextReplacement(
            range: NSRange(location: $0, length: 1),
            replacementText: "y"
        ) }
        system.apply(EditorEditTransaction(replacements: replacements))

        #expect(system.text == String(repeating: "y", count: 100))
    }
}
