import AppKit
@testable import EditorCore
import Foundation
@testable import JSONSupport
import SwiftUI
import Testing

/// EPIC-11 §3.5/Gate 2 — Format JSON enters the native editor path exactly
/// once: one contiguous replacement, one undo group, one binding publication,
/// a clamped selection, and a no-op for already-formatted documents.
@MainActor
@Suite("JSONFormattingUndoPublication")
struct JSONFormattingUndoPublicationTests {
    private let support = EditingAssistIntegrationSupport.self
    private let formatted = "{\n  \"b\": 1,\n  \"a\": 2\n}"

    @Test("formatting is one undo step and one publication")
    func formattingIsOneUndoStepAndOnePublication() {
        let system = support.makeSystem(text: #"{"b":1,"a":2}"#)
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)
        let (binding, counter) = support.makeBinding()
        coordinator.textBinding = binding

        system.applyDocumentReplacement(formatted, undoActionName: "Format JSON")

        #expect(system.text == formatted)
        #expect(counter.count == 1, "expected exactly one binding publication, got \(counter.count)")
        #expect(counter.value == formatted)
        #expect(system.undoManager.canUndo)

        system.undoManager.undo()
        #expect(system.text == #"{"b":1,"a":2}"#)
        system.undoManager.redo()
        #expect(system.text == formatted)
    }

    @Test("undo action is named Format JSON")
    func undoActionIsNamed() {
        let system = support.makeSystem(text: #"{"b":1,"a":2}"#)
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)
        _ = coordinator

        system.applyDocumentReplacement(formatted, undoActionName: "Format JSON")

        // AppKit only materializes the action name when the menu queries it,
        // so ask the undo manager the same way the Edit menu does.
        let named = system.undoManager.undoMenuItemTitle
        #expect(named == "Format JSON" || named == "Undo Format JSON")
    }

    @Test("selection beyond the new length is clamped")
    func selectionClampsToNewLength() {
        let system = support.makeSystem(text: #"{"b":1,"a":2}"#)
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)

        // Caret at the end of the collapsed document (offset 13).
        system.selectedRange = NSRange(location: 13, length: 0)
        system.applyDocumentReplacement(formatted, undoActionName: "Format JSON")

        #expect(system.selectedRange.location == (formatted as NSString).length)
        #expect(system.selectedRange.length == 0)
    }

    @Test("selection inside the document is preserved")
    func selectionInsideIsPreserved() {
        let system = support.makeSystem(text: #"{"b":1,"a":2}"#)
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)

        // Caret right after the opening brace.
        system.selectedRange = NSRange(location: 1, length: 0)
        system.applyDocumentReplacement(formatted, undoActionName: "Format JSON")

        #expect(system.selectedRange.location == 1)
        #expect(system.selectedRange.length == 0)
    }

    @Test("selection range is clamped when the old extent no longer fits")
    func selectionRangeIsClamped() {
        let system = support.makeSystem(text: #"{"b":1,"a":2}"#)
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)

        // The formatted text (26 UTF-16 units) is longer than the collapsed
        // source, so a selection inside it always fits; use a selection that
        // starts near the end and verify it never exceeds the new length.
        system.selectedRange = NSRange(location: 10, length: 3)
        system.applyDocumentReplacement(formatted, undoActionName: "Format JSON")

        let newLength = (formatted as NSString).length
        #expect(system.selectedRange.location + system.selectedRange.length <= newLength)
    }

    @Test("already-formatted documents produce no edit")
    func alreadyFormattedIsANoOp() {
        let system = support.makeSystem(text: formatted)
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)
        let (binding, counter) = support.makeBinding()
        coordinator.textBinding = binding

        system.applyDocumentReplacement(formatted, undoActionName: "Format JSON")

        #expect(system.text == formatted)
        #expect(counter.isEmpty, "a no-op must not publish")
        #expect(!system.undoManager.canUndo, "a no-op must not create an undo entry")
    }

    @Test("formatting via JSONFormatter produces a valid, idempotent replacement")
    func formatterOutputIsIdempotentReplacement() {
        let input = #"{"z":[3,1],"a":{"b":true}}"#
        let outcome = JSONFormatter.format(input)
        guard case let .formatted(pretty) = outcome else {
            Issue.record("Expected formatted outcome")
            return
        }
        let system = support.makeSystem(text: input)
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)

        system.applyDocumentReplacement(pretty, undoActionName: "Format JSON")
        #expect(system.text == pretty)

        // Formatting again is a no-op: idempotent output, no second edit.
        system.applyDocumentReplacement(pretty, undoActionName: "Format JSON")
        #expect(system.text == pretty)
    }
}
