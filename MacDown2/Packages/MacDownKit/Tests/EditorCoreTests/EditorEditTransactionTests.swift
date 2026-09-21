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

    // MARK: - `validating(orderedDescending:documentLength:)` (pure, no AppKit)

    /// Unlike `apply(_:)` itself (whose `assertionFailure` on invalid input
    /// traps in a normal Debug test run), this pure validation logic can be
    /// exercised directly against genuinely malformed input in any build
    /// configuration -- closing the gap an earlier hostile review found:
    /// the "Release silently drops the bad subset" claim previously had
    /// zero test coverage.
    @Test func validatingAcceptsAllNonOverlappingInBoundsReplacements() {
        let replacements = [
            TextReplacement(range: NSRange(location: 8, length: 3), replacementText: "dog"),
            TextReplacement(range: NSRange(location: 4, length: 3), replacementText: "dog"),
            TextReplacement(range: NSRange(location: 0, length: 3), replacementText: "dog"),
        ]
        let result = EditorEditTransaction.validating(orderedDescending: replacements, documentLength: 11)
        #expect(result.applied == replacements)
        #expect(!result.hadInvalidReplacement)
    }

    @Test func validatingDropsFromTheFirstOverlap() {
        // Sorted highest-to-lowest; [4,3) and [2,3) overlap (2+3=5 > 4).
        let replacements = [
            TextReplacement(range: NSRange(location: 4, length: 3), replacementText: "X"),
            TextReplacement(range: NSRange(location: 2, length: 3), replacementText: "Y"),
        ]
        let result = EditorEditTransaction.validating(orderedDescending: replacements, documentLength: 10)
        #expect(result.applied == [replacements[0]])
        #expect(result.hadInvalidReplacement)
    }

    @Test func validatingDropsAnOutOfBoundsReplacement() {
        let replacements = [
            TextReplacement(range: NSRange(location: 5, length: 10), replacementText: "X"),
        ]
        let result = EditorEditTransaction.validating(orderedDescending: replacements, documentLength: 8)
        #expect(result.applied.isEmpty)
        #expect(result.hadInvalidReplacement)
    }

    @Test func validatingKeepsTheValidPrefixBeforeAnInvalidEntry() {
        // Processed highest-offset-first: the higher, valid entry is
        // accepted before the lower, out-of-bounds one is reached and the
        // scan stops -- a malformed transaction fails closed on everything
        // from the first bad entry onward, but keeps what was already
        // validated as safe.
        let valid = TextReplacement(range: NSRange(location: 5, length: 2), replacementText: "ok")
        let replacements = [
            valid,
            TextReplacement(range: NSRange(location: -1, length: 1), replacementText: "bad"),
        ]
        let result = EditorEditTransaction.validating(orderedDescending: replacements, documentLength: 8)
        #expect(result.applied == [valid])
        #expect(result.hadInvalidReplacement)
    }

    @Test func validatingRejectsANegativeLocation() {
        let replacements = [
            TextReplacement(range: NSRange(location: -1, length: 1), replacementText: "X"),
        ]
        let result = EditorEditTransaction.validating(orderedDescending: replacements, documentLength: 10)
        #expect(result.applied.isEmpty)
        #expect(result.hadInvalidReplacement)
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
