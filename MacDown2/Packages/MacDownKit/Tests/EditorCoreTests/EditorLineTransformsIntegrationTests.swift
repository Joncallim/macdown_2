import AppKit
@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 §6.13, Slice 4c-i — `EditorTextSystem`'s own adapter methods
/// (`duplicateLines()`/`deleteLines()`/`moveLinesUp()`/`moveLinesDown()`/
/// `joinLines()`), mounted against a real `NSTextView`/window so the
/// resulting text, selection, undo registration, and `lineIndex`
/// incremental-update path are all exercised for real -- `EditorLineTransforms`
/// itself already has its own exhaustive pure-logic suite
/// (`EditorLineTransformsTests.swift`); these tests are specifically about
/// the ADAPTER's own wiring, not the transform logic.
@MainActor
@Suite("EditorTextSystem line-reordering transforms (Slice 4c-i)")
struct EditorLineTransformsIntegrationTests {
    private let support = EditingAssistIntegrationSupport.self

    @Test func duplicateLinesUpdatesTextSelectionAndLineIndex() {
        let system = support.makeSystem(text: "AAA\nBBB\nCCC")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system) // lineIndex updates via the delegate hook
        system.selectedRange = NSRange(location: 5, length: 0) // inside "BBB"

        let handled = system.duplicateLines()

        #expect(handled)
        #expect(system.textView.string == "AAA\nBBB\nBBB\nCCC")
        #expect(system.selectedRange == NSRange(location: 9, length: 0))
        // The line index must reflect the newly-inserted line, not just the
        // raw text -- confirmed via its own incremental-update path, the
        // same one every other multi-range command already relies on.
        #expect(system.lineIndex.lineCount == 4)
        #expect(system.lineIndex.line(atUTF16Offset: 9) == 3)
    }

    @Test func deleteLinesRemovesTheLineAndRegistersOneUndoStep() {
        let system = support.makeSystem(text: "AAA\nBBB\nCCC")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: 5, length: 0)

        let handled = system.deleteLines()

        #expect(handled)
        #expect(system.textView.string == "AAA\nCCC")
        #expect(system.lineIndex.lineCount == 2)
        #expect(system.textView.undoManager?.canUndo == true)
        system.textView.undoManager?.undo()
        #expect(system.textView.string == "AAA\nBBB\nCCC")
    }

    @Test func moveLinesUpAtDocumentStartIsANoOpThatChangesNothing() {
        let system = support.makeSystem(text: "AAA\nBBB")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 0)

        let handled = system.moveLinesUp()

        #expect(handled == false)
        #expect(system.textView.string == "AAA\nBBB")
    }

    @Test func moveLinesDownSwapsWithTheFollowingLine() {
        let system = support.makeSystem(text: "AAA\nBBB\nCCC")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 0)

        let handled = system.moveLinesDown()

        #expect(handled)
        #expect(system.textView.string == "BBB\nAAA\nCCC")
    }

    @Test func joinLinesMergesTheCurrentAndFollowingLine() {
        let system = support.makeSystem(text: "foo\n  bar")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 0)

        let handled = system.joinLines()

        #expect(handled)
        #expect(system.textView.string == "foo bar")
    }

    @Test func lineTransformOnAnEmptyDocumentDoesNothing() {
        let system = support.makeSystem(text: "")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        #expect(system.deleteLines() == false)
        #expect(system.joinLines() == false)
        #expect(system.moveLinesUp() == false)
        #expect(system.moveLinesDown() == false)
        #expect(system.textView.string == "")
    }
}
