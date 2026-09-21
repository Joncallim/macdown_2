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
